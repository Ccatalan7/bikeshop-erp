import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_geometry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';

Map<String, dynamic> _block({
  required String id,
  String blockType = 'text',
  dynamic orderIndex,
  dynamic sortOrder,
  dynamic isVisible = true,
  Map<String, dynamic> blockData = const <String, dynamic>{},
  bool omitOrderIndex = false,
  bool omitSortOrder = true,
  bool omitVisibility = false,
}) {
  return <String, dynamic>{
    'id': id,
    'block_type': blockType,
    if (!omitOrderIndex) 'order_index': orderIndex,
    if (!omitSortOrder) 'sort_order': sortOrder,
    if (!omitVisibility) 'is_visible': isVisible,
    'block_data': blockData,
  };
}

List<String> _ids(WebsitePageComposition composition) {
  return composition.blocks.map((block) => block.id).toList();
}

void main() {
  group('WebsitePageComposition visibility', () {
    final blocks = <Map<String, dynamic>>[
      _block(
        id: 'global-hidden',
        orderIndex: 1,
        isVisible: false,
      ),
      _block(
        id: 'mobile-hidden',
        orderIndex: 2,
        blockData: <String, dynamic>{
          'visibility': <String, dynamic>{'mobile': false},
        },
      ),
      _block(
        id: 'all-breakpoints-hidden',
        orderIndex: 3,
        blockData: <String, dynamic>{
          'visibility': <String, dynamic>{
            'desktop': false,
            'tablet': false,
            'mobile': false,
          },
        },
      ),
      _block(
        id: 'missing-global-visibility',
        orderIndex: 4,
        omitVisibility: true,
      ),
      _block(
        id: 'json-visibility',
        orderIndex: 5,
        blockData: <String, dynamic>{
          'visibility': '{"mobile":"false","desktop":"true"}',
        },
      ),
      _block(id: 'visible', orderIndex: 6),
    ];

    test('Edit exposes hidden blocks so they remain repairable', () {
      final composition = WebsitePageComposition.project(
        blocks: blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'mobile',
      );

      expect(
        _ids(composition),
        <String>[
          'global-hidden',
          'mobile-hidden',
          'all-breakpoints-hidden',
          'missing-global-visibility',
          'json-visibility',
          'visible',
        ],
      );
      expect(composition.blocks.first.isGloballyVisible, isFalse);
      expect(
        composition.blocks[1].responsiveVisibility['mobile'],
        isFalse,
      );
    });

    test('Preview and public use the canonical current-breakpoint helper', () {
      final preview = WebsitePageComposition.project(
        blocks: blocks,
        mode: WebsitePageCompositionMode.preview,
        breakpoint: ' MOBILE ',
      );
      final public = WebsitePageComposition.project(
        blocks: blocks,
        mode: WebsitePageCompositionMode.public,
        breakpoint: 'mobile',
      );
      final desktopPreview = WebsitePageComposition.project(
        blocks: blocks,
        mode: WebsitePageCompositionMode.preview,
        breakpoint: 'desktop',
      );

      expect(
        _ids(preview),
        <String>['missing-global-visibility', 'visible'],
      );
      expect(_ids(public), _ids(preview));
      expect(public.breakpoint, 'mobile');
      expect(
        _ids(desktopPreview),
        <String>[
          'mobile-hidden',
          'missing-global-visibility',
          'json-visibility',
          'visible',
        ],
      );
    });

    test('rejects a non-canonical breakpoint instead of guessing', () {
      expect(
        () => WebsitePageComposition.project(
          blocks: blocks,
          mode: WebsitePageCompositionMode.public,
          breakpoint: 'watch',
        ),
        throwsArgumentError,
      );
    });

    test('logical width resolves each block visibility generation separately',
        () {
      final mixed = <Map<String, dynamic>>[
        _block(
          id: 'legacy',
          orderIndex: 0,
          blockData: <String, dynamic>{
            'visibility': <String, dynamic>{
              'mobile': true,
              'tablet': false,
              'desktop': true,
            },
            'responsive': <String, dynamic>{
              'version': 2,
              'mobile': <String, dynamic>{'focalPointX': .7},
            },
          },
        ),
        _block(
          id: 'canonical',
          orderIndex: 1,
          blockData: <String, dynamic>{
            'visibility': <String, dynamic>{
              'version': 2,
              'mobile': true,
              'tablet': false,
              'desktop': true,
            },
          },
        ),
      ];

      final at620 = WebsitePageComposition.project(
        blocks: mixed,
        mode: WebsitePageCompositionMode.public,
        breakpoint: 'mobile',
        logicalWidth: 620,
      );
      final at1000 = WebsitePageComposition.project(
        blocks: mixed,
        mode: WebsitePageCompositionMode.public,
        breakpoint: 'tablet',
        logicalWidth: 1000,
      );

      expect(_ids(at620), <String>['legacy']);
      expect(_ids(at1000), <String>['canonical']);
      expect(at620.logicalWidth, 620);
    });
  });

  group('WebsitePageComposition ordering', () {
    test('order_index wins, sort_order is legacy fallback, ties are stable',
        () {
      final composition = WebsitePageComposition.project(
        blocks: <Map<String, dynamic>>[
          _block(id: 'tie-first', orderIndex: '5'),
          _block(
            id: 'canonical-wins',
            orderIndex: 10,
            sortOrder: -100,
            omitSortOrder: false,
          ),
          _block(
            id: 'legacy',
            orderIndex: null,
            sortOrder: '3',
            omitOrderIndex: true,
            omitSortOrder: false,
          ),
          _block(id: 'tie-second', orderIndex: 5.0),
          _block(
            id: 'invalid-canonical',
            orderIndex: 'not-an-order',
            sortOrder: 4,
            omitSortOrder: false,
          ),
          _block(
            id: 'no-order',
            orderIndex: null,
            omitOrderIndex: true,
          ),
          _block(
            id: 'fractional-canonical',
            orderIndex: 1.5,
            sortOrder: 2,
            omitSortOrder: false,
          ),
        ],
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );

      expect(
        _ids(composition),
        <String>[
          'no-order',
          'fractional-canonical',
          'legacy',
          'invalid-canonical',
          'tie-first',
          'tie-second',
          'canonical-wins',
        ],
      );
      expect(
        composition.blocks
            .where((block) => block.id.startsWith('tie-'))
            .map((block) => block.sourceIndex),
        <int>[0, 3],
      );
      expect(
        composition.blocks
            .firstWhere((block) => block.id == 'canonical-wins')
            .orderIndex,
        10,
      );
    });
  });

  group('WebsitePageComposition ownership', () {
    test('does not mutate inputs and owns an immutable deep copy', () {
      final nestedItem = <String, dynamic>{'label': 'original'};
      final nestedData = <String, dynamic>{
        'nested': <String, dynamic>{'enabled': true},
        'items': <dynamic>[nestedItem],
        'spacingAfter': 12,
      };
      final input = <Map<String, dynamic>>[
        _block(
          id: 'deep-copy',
          orderIndex: 0,
          blockData: nestedData,
        ),
      ];
      final expectedInput = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'deep-copy',
          'block_type': 'text',
          'order_index': 0,
          'is_visible': true,
          'block_data': <String, dynamic>{
            'nested': <String, dynamic>{'enabled': true},
            'items': <dynamic>[
              <String, dynamic>{'label': 'original'},
            ],
            'spacingAfter': 12,
          },
        },
      ];

      final composition = WebsitePageComposition.project(
        blocks: input,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );
      final projected = composition.blocks.single;

      expect(input, expectedInput);
      expect(identical(projected.sourceBlock, input.single), isFalse);
      expect(identical(projected.blockData, nestedData), isFalse);
      expect(
        identical(
          (projected.blockData['items'] as List).single,
          nestedItem,
        ),
        isFalse,
      );

      (nestedData['nested'] as Map<String, dynamic>)['enabled'] = false;
      nestedItem['label'] = 'changed';
      nestedData['new-field'] = true;

      expect(
        projected.blockData,
        <String, dynamic>{
          'nested': <String, dynamic>{'enabled': true},
          'items': <dynamic>[
            <String, dynamic>{'label': 'original'},
          ],
          'spacingAfter': 12,
        },
      );
      expect(
        () => projected.sourceBlock['new-field'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => projected.blockData['new-field'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => (projected.blockData['items'] as List).add('new-item'),
        throwsUnsupportedError,
      );
      expect(
        () => composition.blocks.add(projected),
        throwsUnsupportedError,
      );
    });
  });

  group('WebsitePageComposition geometry', () {
    test('height and spacing use the same responsive meta owner', () {
      final blocks = <Map<String, dynamic>>[
        _block(
          id: 'responsive-layout',
          blockType: 'hero',
          orderIndex: 0,
          blockData: <String, dynamic>{
            'blockHeight': 640,
            'spacingAfter': 72,
            'responsive': <String, dynamic>{
              'version': 2,
              'mobile': <String, dynamic>{
                'blockHeight': 360,
                'spacingAfter': 24,
              },
            },
          },
        ),
      ];

      final mobile = WebsitePageComposition.project(
        blocks: blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'mobile',
        logicalWidth: 390,
      ).blocks.single.geometry;
      final desktop = WebsitePageComposition.project(
        blocks: blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
        logicalWidth: 1440,
      ).blocks.single.geometry;

      expect(mobile.blockHeight, 360);
      expect(mobile.spacingAfter, 24);
      expect(desktop.blockHeight, 640);
      expect(desktop.spacingAfter, 72);
    });

    test('normalizes finite spacing with one bounded theme fallback', () {
      final composition = WebsitePageComposition.project(
        blocks: <Map<String, dynamic>>[
          _block(id: 'fallback', orderIndex: 0),
          _block(
            id: 'negative',
            orderIndex: 1,
            blockData: <String, dynamic>{'spacingAfter': -12},
          ),
          _block(
            id: 'too-large',
            orderIndex: 2,
            blockData: <String, dynamic>{'spacingAfter': 999},
          ),
          _block(
            id: 'nan',
            orderIndex: 3,
            blockData: <String, dynamic>{'spacingAfter': double.nan},
          ),
          _block(
            id: 'infinity',
            orderIndex: 4,
            blockData: <String, dynamic>{
              'spacingAfter': double.infinity,
            },
          ),
          _block(
            id: 'numeric-string',
            orderIndex: 5,
            blockData: <String, dynamic>{'spacingAfter': '32.5'},
          ),
        ],
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
        sectionSpacing: 48,
      );
      final spacingById = <String, double>{
        for (final block in composition.blocks)
          block.id: block.geometry.spacingAfter,
      };

      expect(
        spacingById,
        <String, double>{
          'fallback': 48,
          'negative': 0,
          'too-large': 200,
          'nan': 48,
          'infinity': 48,
          'numeric-string': 32.5,
        },
      );

      final boundedFallback = WebsitePageComposition.project(
        blocks: <Map<String, dynamic>>[
          _block(id: 'bounded', orderIndex: 0),
        ],
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
        sectionSpacing: 999,
      );
      final invalidFallback = WebsitePageComposition.project(
        blocks: <Map<String, dynamic>>[
          _block(id: 'defaulted', orderIndex: 0),
        ],
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
        sectionSpacing: double.nan,
      );

      expect(boundedFallback.blocks.single.geometry.spacingAfter, 200);
      expect(
        invalidFallback.blocks.single.geometry.spacingAfter,
        WebsitePageComposition.defaultSectionSpacing,
      );
    });

    test('resolves explicit fullBleed before registered/type defaults', () {
      final composition = WebsitePageComposition.project(
        blocks: <Map<String, dynamic>>[
          _block(id: 'hero-default', blockType: 'hero', orderIndex: 0),
          _block(
            id: 'hero-opt-out',
            blockType: 'hero',
            orderIndex: 1,
            blockData: <String, dynamic>{'fullBleed': 'false'},
          ),
          _block(
            id: 'text-opt-in',
            orderIndex: 2,
            blockData: <String, dynamic>{'fullBleed': 1},
          ),
          _block(id: 'text-default', orderIndex: 3),
          _block(
            id: 'category-default',
            blockType: 'categorygrid',
            orderIndex: 4,
          ),
          _block(
            id: 'canvas-registry-default',
            blockType: 'canvas',
            orderIndex: 5,
          ),
          _block(
            id: 'unknown-opt-in',
            blockType: 'futureBlock',
            orderIndex: 6,
            blockData: <String, dynamic>{'fullBleed': true},
          ),
        ],
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );
      final fullBleedById = <String, bool>{
        for (final block in composition.blocks)
          block.id: block.geometry.fullBleed,
      };

      expect(
        fullBleedById,
        <String, bool>{
          'hero-default': true,
          'hero-opt-out': false,
          'text-opt-in': true,
          'text-default': false,
          'category-default': true,
          'canvas-registry-default': false,
          'unknown-opt-in': true,
        },
      );
    });

    test('normalizes valid heights through exact, minimum and intrinsic types',
        () {
      final composition = WebsitePageComposition.project(
        blocks: <Map<String, dynamic>>[
          _block(
            id: 'exact',
            blockType: 'hero',
            orderIndex: 0,
            blockData: <String, dynamic>{'blockHeight': '420'},
          ),
          _block(
            id: 'minimum',
            blockType: 'products',
            orderIndex: 1,
            blockData: <String, dynamic>{'blockHeight': 360},
          ),
          _block(
            id: 'intrinsic',
            blockType: 'text',
            orderIndex: 2,
            blockData: <String, dynamic>{'blockHeight': 220},
          ),
          _block(
            id: 'nan',
            blockType: 'hero',
            orderIndex: 3,
            blockData: <String, dynamic>{'blockHeight': double.nan},
          ),
          _block(
            id: 'infinity',
            blockType: 'products',
            orderIndex: 4,
            blockData: <String, dynamic>{
              'blockHeight': double.infinity,
            },
          ),
          _block(
            id: 'zero',
            blockType: 'carousel',
            orderIndex: 5,
            blockData: <String, dynamic>{'blockHeight': 0},
          ),
          _block(
            id: 'unknown',
            blockType: 'futureBlock',
            orderIndex: 6,
            blockData: <String, dynamic>{'blockHeight': 500},
          ),
        ],
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );
      final byId = <String, WebsitePageCompositionBlock>{
        for (final block in composition.blocks) block.id: block,
      };

      expect(
        byId['exact']!.geometry.heightBehavior,
        WebsitePageBlockHeightBehavior.exact,
      );
      expect(byId['exact']!.geometry.blockHeight, 420);
      expect(byId['exact']!.geometry.exactHeight, 420);
      expect(byId['exact']!.geometry.minimumHeight, isNull);

      expect(
        byId['minimum']!.geometry.heightBehavior,
        WebsitePageBlockHeightBehavior.minimum,
      );
      expect(byId['minimum']!.geometry.blockHeight, 360);
      expect(byId['minimum']!.geometry.minimumHeight, 360);
      expect(byId['minimum']!.geometry.exactHeight, isNull);

      expect(
        byId['intrinsic']!.geometry.heightBehavior,
        WebsitePageBlockHeightBehavior.intrinsic,
      );
      expect(byId['intrinsic']!.geometry.blockHeight, isNull);
      expect(byId['nan']!.geometry.blockHeight, isNull);
      expect(byId['infinity']!.geometry.blockHeight, isNull);
      expect(byId['zero']!.geometry.blockHeight, isNull);
      expect(byId['unknown']!.type, isNull);
      expect(
        byId['unknown']!.geometry.heightBehavior,
        WebsitePageBlockHeightBehavior.intrinsic,
      );
      expect(byId['unknown']!.geometry.blockHeight, isNull);
    });

    test('every registered type has one explicit height behavior', () {
      const exactTypes = <WebsiteBlockType>{
        WebsiteBlockType.hero,
        WebsiteBlockType.carousel,
        WebsiteBlockType.canvas,
        WebsiteBlockType.videoBanner,
      };
      const intrinsicTypes = <WebsiteBlockType>{
        WebsiteBlockType.text,
        WebsiteBlockType.button,
        WebsiteBlockType.divider,
        WebsiteBlockType.footer,
      };
      final minimumTypes =
          WebsiteBlockType.values.toSet().difference(exactTypes).difference(
                intrinsicTypes,
              );

      for (final type in WebsiteBlockType.values) {
        final behavior =
            WebsitePageBlockGeometryProfile.forType(type).heightBehavior;
        if (exactTypes.contains(type)) {
          expect(
            behavior,
            WebsitePageBlockHeightBehavior.exact,
            reason: type.name,
          );
        } else if (intrinsicTypes.contains(type)) {
          expect(
            behavior,
            WebsitePageBlockHeightBehavior.intrinsic,
            reason: type.name,
          );
        } else {
          expect(minimumTypes, contains(type));
          expect(
            behavior,
            WebsitePageBlockHeightBehavior.minimum,
            reason: type.name,
          );
        }
      }
    });
  });
}
