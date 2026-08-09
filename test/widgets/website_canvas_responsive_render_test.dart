import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/website/models/canvas_element_factory.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_canvas_block.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';

/// 7B-1 — the Canvas renderer reads its effective document from the 7A owner.
///
/// These cases pin the three things the round changed: the viewport is
/// classified from the CANVAS width (never the ERP window), a canonical
/// document resolves through `responsive` overrides, and a legacy document
/// renders exactly as it did before, including its 600 px compact boundary.

Map<String, dynamic> _canvasBlock(Map<String, dynamic> data) {
  return <String, dynamic>{
    'id': 'canvas-block',
    'block_type': 'canvas',
    'order_index': 0,
    'is_visible': true,
    'block_data': data,
  };
}

Map<String, dynamic> _carouselBlock(Map<String, dynamic> slide) {
  return <String, dynamic>{
    'id': 'canvas-block',
    'block_type': 'carousel',
    'order_index': 0,
    'is_visible': true,
    'block_data': <String, dynamic>{
      'slides': <Map<String, dynamic>>[slide],
    },
  };
}

Map<String, dynamic> _layer({
  required String id,
  required double x,
  required double y,
  String text = 'Capa',
  Map<String, dynamic>? extra,
}) {
  return createCanvasElement(id: id, type: 'text')
    ..addAll(<String, dynamic>{
      'x': x,
      'y': y,
      'w': 240.0,
      'h': 72.0,
      'text': text,
      ...?extra,
    });
}

/// The canonical persisted override container, exactly as 7A normalises it:
/// `WebsiteResponsiveDataCodec.containerKey` holding
/// `WebsiteResponsiveDataCodec.versionKey` plus the viewport branches.
Map<String, dynamic> _responsive(Map<String, dynamic> viewports) {
  return <String, dynamic>{
    'responsive': <String, dynamic>{
      'version': 2,
      ...viewports,
    },
  };
}

String _breakpoint(double width) {
  return WebsiteViewport.fromLogicalWidth(width).wireName;
}

Finder _layerFinder(String id) =>
    find.byKey(ValueKey<String>('canvas_el_$id'), skipOffstage: false);

Future<void> _preload(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future.wait<void>(<Future<void>>[
      DeferredEditableBlockRenderer.preload(),
      preloadDeferredCanvasLibrary(),
    ]);
  });
}

Future<void> _pumpBlocks(
  WidgetTester tester, {
  required List<Map<String, dynamic>> blocks,
  required double width,
  WebsitePageCompositionMode mode = WebsitePageCompositionMode.public,
  WebsiteEditModeProvider? provider,
  required String settleKey,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  final app = MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PageComposition(
          composition: WebsitePageComposition.project(
            blocks: blocks,
            mode: mode,
            breakpoint: _breakpoint(width),
            logicalWidth: width,
          ),
          primaryColor: const Color(0xFF143D59),
          accentColor: const Color(0xFF00A09D),
          textColor: Colors.black,
          containerPadding: 24,
          onNavigate: (_) {},
          isNavigationEligible: (_) => true,
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    provider == null
        ? app
        : ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: provider,
            child: app,
          ),
  );
  for (var attempt = 0; attempt < 12; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (_layerFinder(settleKey).evaluate().isNotEmpty) break;
  }
}

/// Left edge of a layer relative to the Canvas block, in rendered pixels.
double _layerLeft(WidgetTester tester, String id) {
  final block = find.byKey(
    const ValueKey<String>('page-composition-block-canvas-block'),
  );
  expect(block, findsOneWidget);
  return tester.getRect(_layerFinder(id)).left - tester.getRect(block).left;
}

Rect _canvasRect(WidgetTester tester) {
  final canvas = find.byType(DeferredCanvasBlock);
  expect(canvas, findsOneWidget);
  return tester.getRect(canvas);
}

/// Left edge of a layer relative to the Canvas box, in rendered pixels.
double _layerLeftInCanvas(WidgetTester tester, String id) =>
    tester.getRect(_layerFinder(id)).left - _canvasRect(tester).left;

/// Where a design-space `x` lands for a given effective `designWidth`, using
/// the Canvas box actually measured on screen.
///
/// Asserting against this proves WHICH `designWidth` the owner resolved, which
/// is the measurable consequence of a root-level override.
double _expectedLeft(
  WidgetTester tester, {
  required double designWidth,
  required double designX,
}) {
  final width = _canvasRect(tester).width;
  final scale = (width / designWidth).clamp(0.0, 1.0);
  final offsetX = math.max(0.0, (width - designWidth * scale) / 2);
  return designX * scale + offsetX;
}

/// The layer's effective `x` in DESIGN space.
///
/// Inverts the renderer's own scale/centring from the measured Canvas box, so
/// a standalone Canvas and one nested in a Carousel slide are comparable even
/// when their hosts hand them different available widths.
double _designX(
  WidgetTester tester,
  String id, {
  double designWidth = 1200.0,
}) {
  final width = _canvasRect(tester).width;
  final scale = (width / designWidth).clamp(0.0, 1.0);
  final offsetX = math.max(0.0, (width - designWidth * scale) / 2);
  return (_layerLeftInCanvas(tester, id) - offsetX) / scale;
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets(
    'legacy Canvas keeps its 600 px compact boundary at 620 and 1000',
    (tester) async {
      await _preload(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // No marker, no `responsive` container: a document the migration has
      // never touched. `mobileDesignWidth` plus the hide/show pair are all the
      // per-viewport data it has.
      final data = <String, dynamic>{
        'blockHeight': 480.0,
        'designWidth': 1200.0,
        'mobileDesignWidth': 600.0,
        'fullBleed': true,
        'showGrid': false,
        'elements': <Map<String, dynamic>>[
          _layer(id: 'always', x: 120.0, y: 40.0),
          _layer(
            id: 'wide-only',
            x: 200.0,
            y: 140.0,
            extra: <String, dynamic>{'hideOnMobile': true},
          ),
          _layer(
            id: 'phone-only',
            x: 260.0,
            y: 240.0,
            extra: <String, dynamic>{'showOnMobile': true},
          ),
        ],
      };
      final blocks = <Map<String, dynamic>>[_canvasBlock(data)];
      final before = jsonEncode(blocks);

      // 620 and 1000 are exactly where the document bands 640/1024 disagree
      // with this renderer's own 600 px threshold. Both must stay wide.
      for (final width in <double>[620, 1000]) {
        await _pumpBlocks(
          tester,
          blocks: blocks,
          width: width,
          settleKey: 'always',
        );
        expect(
          _layerFinder('wide-only'),
          findsOneWidget,
          reason: 'hideOnMobile layer must stay visible at $width',
        );
        expect(
          _layerFinder('phone-only'),
          findsNothing,
          reason: 'showOnMobile layer must stay hidden at $width',
        );
        // designWidth 1200 scaled into the canvas, not mobileDesignWidth 600.
        expect(
          _layerLeft(tester, 'always'),
          closeTo(120.0 * (width / 1200.0), 0.01),
          reason: 'designWidth must drive geometry at $width',
        );
      }

      // Below 600 the same legacy document flips, exactly as before 7B.
      await _pumpBlocks(
        tester,
        blocks: blocks,
        width: 590,
        settleKey: 'always',
      );
      expect(_layerFinder('wide-only'), findsNothing);
      expect(_layerFinder('phone-only'), findsOneWidget);
      expect(
        _layerLeft(tester, 'always'),
        closeTo(120.0 * (590.0 / 600.0), 0.01),
        reason: 'mobileDesignWidth must drive geometry below 600',
      );

      expect(
        jsonEncode(blocks),
        before,
        reason: 'reading must not migrate, mark, normalize or save',
      );
    },
  );

  testWidgets(
    'canonical Canvas resolves overrides per viewport without cascade',
    (tester) async {
      await _preload(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final data = <String, dynamic>{
        'canvasResponsiveVersion': 2,
        'blockHeight': 480.0,
        'designWidth': 1200.0,
        'fullBleed': true,
        'showGrid': false,
        'elements': <Map<String, dynamic>>[
          // Declared first, but asks for the last slot on the phone.
          _layer(
            id: 'reordered',
            x: 100.0,
            y: 40.0,
            extra: _responsive(<String, dynamic>{
              'mobile': <String, dynamic>{'order': 1},
              // A tablet-only x must NOT reach the phone.
              'tablet': <String, dynamic>{'x': 700.0},
            }),
          ),
          _layer(id: 'second', x: 300.0, y: 140.0),
          _layer(
            id: 'desktop-only',
            x: 500.0,
            y: 240.0,
            extra: _responsive(<String, dynamic>{
              'mobile': <String, dynamic>{'visible': false},
            }),
          ),
        ],
      };
      final blocks = <Map<String, dynamic>>[_canvasBlock(data)];
      final before = jsonEncode(blocks);

      // 1440 -> desktop: base values, no override reaches it.
      await _pumpBlocks(
        tester,
        blocks: blocks,
        width: 1440,
        settleKey: 'reordered',
      );
      expect(_layerFinder('desktop-only'), findsOneWidget);
      expect(_layerLeft(tester, 'reordered'), closeTo(100.0 + 120.0, 0.01),
          reason: 'desktop keeps base x, centred inside the 1200 design width');

      // 834 -> tablet: the tablet override applies.
      await _pumpBlocks(
        tester,
        blocks: blocks,
        width: 834,
        settleKey: 'reordered',
      );
      expect(_layerFinder('desktop-only'), findsOneWidget);
      expect(
        _layerLeft(tester, 'reordered'),
        closeTo(700.0 * (834.0 / 1200.0), 0.01),
        reason: 'tablet x override must apply at 834',
      );

      // 390 -> mobile: visibility drops the layer, the tablet x does not
      // cascade down, and the phone order moves the first layer behind.
      await _pumpBlocks(
        tester,
        blocks: blocks,
        width: 390,
        settleKey: 'reordered',
      );
      expect(
        _layerFinder('desktop-only'),
        findsNothing,
        reason: 'visible=false hides the layer on the phone',
      );
      expect(
        _layerLeft(tester, 'reordered'),
        closeTo(100.0 * (390.0 / 1200.0), 0.01),
        reason: 'a tablet override must not cascade into mobile',
      );

      // `widgetList` walks the tree depth-first, so for the layer Stack this
      // is paint order.
      final painted = tester
          .widgetList<Positioned>(find.byWidgetPredicate(
            (widget) =>
                widget is Positioned &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>)
                    .value
                    .startsWith('canvas_el_'),
          ))
          .map((widget) => (widget.key! as ValueKey<String>).value)
          .toList();
      expect(
        painted.indexOf('canvas_el_second'),
        lessThan(painted.indexOf('canvas_el_reordered')),
        reason: 'responsive.mobile.order must move the layer to the last slot',
      );

      expect(jsonEncode(blocks), before, reason: 'projection must be pure');
    },
  );

  testWidgets(
    'Edit, Preview and Public project the same effective Canvas document',
    (tester) async {
      await _preload(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final data = <String, dynamic>{
        'canvasResponsiveVersion': 2,
        'blockHeight': 480.0,
        'designWidth': 1200.0,
        'fullBleed': true,
        'showGrid': false,
        'elements': <Map<String, dynamic>>[
          _layer(id: 'shared', x: 160.0, y: 48.0),
          _layer(
            id: 'wide-only',
            x: 320.0,
            y: 180.0,
            extra: _responsive(<String, dynamic>{
              'mobile': <String, dynamic>{'visible': false},
            }),
          ),
        ],
      };
      final blocks = <Map<String, dynamic>>[_canvasBlock(data)];

      for (final width in <double>[390, 834, 1440]) {
        final readings = <WebsitePageCompositionMode, List<Object>>{};
        for (final mode in WebsitePageCompositionMode.values) {
          WebsiteEditModeProvider? provider;
          var hosted = blocks;
          if (mode == WebsitePageCompositionMode.edit) {
            provider = WebsiteEditModeProvider()
              ..enterEditMode(
                blocks,
                const <String, dynamic>{},
                pageId: 'canvas-page',
                pageSlug: 'canvas-page',
              );
            hosted = provider.blocks;
          }
          await _pumpBlocks(
            tester,
            blocks: hosted,
            width: width,
            mode: mode,
            provider: provider,
            settleKey: 'shared',
          );
          readings[mode] = <Object>[
            _layerLeft(tester, 'shared'),
            _layerFinder('wide-only').evaluate().length,
          ];
          await tester.pumpWidget(const SizedBox.shrink());
          provider?.dispose();
        }

        expect(
          readings[WebsitePageCompositionMode.preview],
          readings[WebsitePageCompositionMode.edit],
          reason: 'Edit/Preview must agree at $width',
        );
        expect(
          readings[WebsitePageCompositionMode.public],
          readings[WebsitePageCompositionMode.preview],
          reason: 'Preview/Public must agree at $width',
        );
        expect(
          readings[WebsitePageCompositionMode.public]![1],
          width < 600 ? 0 : 1,
          reason: 'authoring mode must not change the effective content',
        );
      }
    },
  );

  testWidgets(
    'a Canvas nested in a Carousel slide projects like the standalone owner',
    (tester) async {
      await _preload(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Fresh maps per host: the two documents must stay independent so purity
      // can be asserted on both.
      List<Map<String, dynamic>> layers() => <Map<String, dynamic>>[
            _layer(
              id: 'shared',
              x: 160.0,
              y: 48.0,
              extra: _responsive(<String, dynamic>{
                'tablet': <String, dynamic>{'x': 700.0},
              }),
            ),
            _layer(
              id: 'wide-only',
              x: 320.0,
              y: 180.0,
              extra: _responsive(<String, dynamic>{
                'mobile': <String, dynamic>{'visible': false},
              }),
            ),
          ];

      final slide = <String, dynamic>{
        'useComposition': true,
        // The slide declares the canonical contract explicitly.
        'canvasResponsiveVersion': 2,
        'designWidth': 1200.0,
        'mobileDesignWidth': 1200.0,
        'designHeight': 480.0,
        'elements': layers(),
      };
      final nested = <Map<String, dynamic>>[_carouselBlock(slide)];
      final standalone = <Map<String, dynamic>>[
        _canvasBlock(<String, dynamic>{
          'canvasResponsiveVersion': 2,
          'blockHeight': 480.0,
          'designWidth': 1200.0,
          'mobileDesignWidth': 1200.0,
          'fullBleed': true,
          'showGrid': false,
          'elements': layers(),
        }),
      ];
      final beforeNested = jsonEncode(nested);
      final beforeStandalone = jsonEncode(standalone);

      // Effective design-space x per viewport: the tablet override applies at
      // tablet only and never cascades down to the phone.
      final expectedDesignX = <double, double>{
        390: 160.0,
        834: 700.0,
        1440: 160.0,
      };

      for (final width in <double>[390, 834, 1440]) {
        await _pumpBlocks(
          tester,
          blocks: standalone,
          width: width,
          settleKey: 'shared',
        );
        final standaloneX = _designX(tester, 'shared');
        final standaloneVisible = _layerFinder('wide-only').evaluate().length;

        await _pumpBlocks(
          tester,
          blocks: nested,
          width: width,
          settleKey: 'shared',
        );
        final nestedX = _designX(tester, 'shared');

        expect(
          standaloneX,
          closeTo(expectedDesignX[width]!, 0.01),
          reason: 'standalone Canvas must resolve the tablet x override only '
              'at tablet, at $width',
        );
        expect(
          nestedX,
          closeTo(standaloneX, 0.01),
          reason: 'nested Canvas must resolve the same effective geometry as '
              'standalone at $width',
        );
        expect(
          _layerFinder('wide-only').evaluate().length,
          standaloneVisible,
          reason: 'nested Canvas must resolve visibility like standalone '
              'at $width',
        );
        expect(
          standaloneVisible,
          width < 600 ? 0 : 1,
          reason: 'the layer is hidden only on the phone',
        );
      }

      expect(
        jsonEncode(nested),
        beforeNested,
        reason: 'nested projection must be pure',
      );
      expect(
        jsonEncode(standalone),
        beforeStandalone,
        reason: 'standalone projection must be pure',
      );
    },
  );

  testWidgets(
    'a root-only canonical slide forwards its contract to the nested Canvas',
    (tester) async {
      await _preload(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // No layer carries a `responsive` container: the whole contract lives at
      // the slide root, so this only works if the marker and the root
      // container travel into the nested composition document.
      List<Map<String, dynamic>> layers() => <Map<String, dynamic>>[
            _layer(id: 'shared', x: 160.0, y: 48.0),
          ];
      final rootContract = <String, dynamic>{
        'canvasResponsiveVersion': 2,
        ..._responsive(<String, dynamic>{
          // The owner's own root key, not a second alias.
          'tablet': <String, dynamic>{'designWidth': 600.0},
        }),
      };

      final slide = <String, dynamic>{
        'useComposition': true,
        ...rootContract,
        'designWidth': 1200.0,
        'mobileDesignWidth': 1200.0,
        'designHeight': 480.0,
        'elements': layers(),
      };
      final nested = <Map<String, dynamic>>[_carouselBlock(slide)];
      final standalone = <Map<String, dynamic>>[
        _canvasBlock(<String, dynamic>{
          ...rootContract,
          'blockHeight': 480.0,
          'designWidth': 1200.0,
          'mobileDesignWidth': 1200.0,
          'fullBleed': true,
          'showGrid': false,
          'elements': layers(),
        }),
      ];
      final beforeNested = jsonEncode(nested);
      final beforeStandalone = jsonEncode(standalone);

      // The tablet override replaces the coordinate system at tablet only. On
      // the phone the legacy mobile alias still wins and the tablet value must
      // not cascade down.
      final expectedDesignWidth = <double, double>{
        390: 1200.0,
        834: 600.0,
        1440: 1200.0,
      };

      for (final width in <double>[390, 834, 1440]) {
        await _pumpBlocks(
          tester,
          blocks: standalone,
          width: width,
          settleKey: 'shared',
        );
        final standaloneLeft = _layerLeftInCanvas(tester, 'shared');
        expect(
          standaloneLeft,
          closeTo(
            _expectedLeft(
              tester,
              designWidth: expectedDesignWidth[width]!,
              designX: 160.0,
            ),
            0.01,
          ),
          reason: 'standalone must resolve designWidth '
              '${expectedDesignWidth[width]} at $width',
        );

        await _pumpBlocks(
          tester,
          blocks: nested,
          width: width,
          settleKey: 'shared',
        );
        expect(
          _layerLeftInCanvas(tester, 'shared'),
          closeTo(standaloneLeft, 0.01),
          reason: 'nested Canvas must resolve the root override like '
              'standalone at $width',
        );
      }

      expect(
        jsonEncode(nested),
        beforeNested,
        reason: 'nested projection must be pure',
      );
      expect(
        jsonEncode(standalone),
        beforeStandalone,
        reason: 'standalone projection must be pure',
      );
    },
  );
}
