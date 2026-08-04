import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_document_sanitizer.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_save_coordinator.dart';

void main() {
  group('Website Canvas document sanitization', () {
    test(
      'ingress removes only type-owned transient selection metadata',
      () {
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(
            _legacySelectionBlocks(),
            const <String, dynamic>{},
            pageId: 'page-a',
            pageSlug: 'landing',
          );
        addTearDown(provider.dispose);

        final canvas = provider.getBlockData('canvas-1');
        expect(canvas.containsKey('activeElementId'), isFalse);
        expect(canvas['title'], 'Canvas persisted title');
        expect(
          (canvas['metadata'] as Map)['activeElementId'],
          'nested-canvas-value',
        );
        expect(
          ((canvas['elements'] as List).single as Map)['activeElementId'],
          'element-owned-value',
        );

        final carousel = provider.getBlockData('carousel-1');
        expect(carousel['activeElementId'], 'carousel-root-domain-value');
        final firstSlide = (carousel['slides'] as List).first as Map;
        expect(firstSlide.containsKey('activeElementId'), isFalse);
        expect(firstSlide['title'], 'Persisted slide');
        expect(
          (firstSlide['metadata'] as Map)['activeElementId'],
          'nested-slide-value',
        );
        expect(
          ((firstSlide['elements'] as List).single as Map)['activeElementId'],
          'slide-element-owned-value',
        );

        expect(
          provider.getBlockData('about-1')['activeElementId'],
          'about-domain-value',
        );
      },
    );

    test(
      'mutation, acknowledgment, undo and redo never serialize selection',
      () {
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(
            _cleanLifecycleBlocks(),
            const <String, dynamic>{},
            pageId: 'page-a',
            pageSlug: 'landing',
          );
        addTearDown(provider.dispose);

        provider.selectCanvasElement('canvas-1', 'canvas-second');
        expect(provider.hasPageDraftChanges, isFalse);
        expect(provider.canUndo, isFalse);

        provider.updateBlockData(
          'canvas-1',
          'elements',
          <Map<String, dynamic>>[
            _canvasElement('canvas-first'),
          ],
        );

        expect(provider.canvasElementSelection('canvas-1'), isNull);
        expect(provider.hasPageDraftChanges, isTrue);
        expect(provider.canUndo, isTrue);
        _expectTransientSelectionAbsent(provider.blocks);

        provider.undo();
        expect(
          (provider.getBlockData('canvas-1')['elements'] as List),
          hasLength(2),
        );
        expect(provider.canvasElementSelection('canvas-1'), isNull);
        _expectTransientSelectionAbsent(provider.blocks);

        provider.redo();
        expect(
          (provider.getBlockData('canvas-1')['elements'] as List),
          hasLength(1),
        );
        expect(provider.canvasElementSelection('canvas-1'), isNull);
        _expectTransientSelectionAbsent(provider.blocks);

        provider.selectCanvasElement(
          'carousel-1',
          'slide-second-element',
          slideIndex: 1,
          slideCount: 2,
        );
        provider.updateBlockData(
          'carousel-1',
          'slides',
          <Map<String, dynamic>>[
            _carouselSlide(
              id: 'slide-first',
              elementId: 'slide-first-element',
              activeElementId: 'must-not-enter-history',
            ),
          ],
        );

        expect(
          provider.canvasElementSelection('carousel-1', slideIndex: 1),
          isNull,
        );
        _expectTransientSelectionAbsent(provider.blocks);

        provider.undo();
        expect(
          (provider.getBlockData('carousel-1')['slides'] as List),
          hasLength(2),
        );
        expect(
          provider.canvasElementSelection('carousel-1', slideIndex: 1),
          isNull,
        );
        _expectTransientSelectionAbsent(provider.blocks);

        provider.redo();
        _expectTransientSelectionAbsent(provider.blocks);

        provider.updateBlockData(
          'canvas-1',
          'activeElementId',
          'legacy-mutation',
        );
        expect(
          provider.getBlockData('canvas-1').containsKey('activeElementId'),
          isFalse,
        );

        final attempted = provider.blocks;
        final fresh = _withLegacySelectionMetadata(attempted);
        provider.acknowledgeSavedBlocks(
          attemptedBlocks: attempted,
          freshBlocks: fresh,
        );

        _expectTransientSelectionAbsent(provider.blocks);
        expect(provider.canUndo, isFalse);
        expect(provider.canRedo, isFalse);

        final command = WebsiteEditorSaveCommand.capture(
          tenantId: 'tenant-a',
          document: provider,
        );
        _expectTransientSelectionAbsent(command.blocks);
      },
    );

    test(
      'a transient-only legacy mutation never dirties the draft or history',
      () {
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(
            _cleanLifecycleBlocks(),
            const <String, dynamic>{},
            pageId: 'page-a',
            pageSlug: 'landing',
          );
        addTearDown(provider.dispose);

        provider.updateBlockData(
          'canvas-1',
          'activeElementId',
          'legacy-transient-selection',
        );

        expect(
          provider.getBlockData('canvas-1').containsKey('activeElementId'),
          isFalse,
        );
        expect(
          provider.hasPageDraftChanges,
          isFalse,
          reason: 'Selection alone must never enable Guardar.',
        );
        expect(provider.canUndo, isFalse);
      },
    );

    test(
      'delete clears standalone and nested Canvas selection permanently',
      () {
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(
            _cleanLifecycleBlocks(),
            const <String, dynamic>{},
            pageId: 'page-a',
            pageSlug: 'landing',
          );
        addTearDown(provider.dispose);

        provider.selectCanvasElement('canvas-1', 'canvas-first');
        expect(provider.canvasElementSelection('canvas-1'), 'canvas-first');
        provider.deleteBlock('canvas-1');

        expect(provider.canvasElementSelection('canvas-1'), isNull);
        expect(provider.selectedCanvasElementId, isNull);

        provider.undo();
        expect(provider.getBlock('canvas-1'), isNotNull);
        expect(provider.canvasElementSelection('canvas-1'), isNull);

        provider.selectCanvasElement(
          'carousel-1',
          'slide-second-element',
          slideIndex: 1,
          slideCount: 2,
        );
        expect(
          provider.canvasElementSelection('carousel-1', slideIndex: 1),
          'slide-second-element',
        );
        provider.deleteBlock('carousel-1');

        expect(
          provider.canvasElementSelection('carousel-1', slideIndex: 1),
          isNull,
        );
        expect(provider.selectedCanvasElementId, isNull);

        provider.undo();
        expect(provider.getBlock('carousel-1'), isNotNull);
        expect(
          provider.canvasElementSelection('carousel-1', slideIndex: 1),
          isNull,
        );
        _expectTransientSelectionAbsent(provider.blocks);
      },
    );

    test(
      'save command is type-aware and preserves unrelated homonymous fields',
      () {
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(
            _legacySelectionBlocks(),
            const <String, dynamic>{},
            pageId: 'page-a',
            pageSlug: 'landing',
          );
        addTearDown(provider.dispose);

        provider.updateBlockData('canvas-1', 'title', 'Save this Canvas');

        final command = WebsiteEditorSaveCommand.capture(
          tenantId: 'tenant-a',
          document: provider,
        );

        _expectTransientSelectionAbsent(command.blocks);
        expect(
          _dataFor(command.blocks, 'about-1')['activeElementId'],
          'about-domain-value',
        );
        expect(
          _dataFor(command.blocks, 'carousel-1')['activeElementId'],
          'carousel-root-domain-value',
        );
        expect(
          (_dataFor(command.blocks, 'canvas-1')['metadata']
              as Map)['activeElementId'],
          'nested-canvas-value',
        );
      },
    );

    test(
      'responsive branches are deep-copied and transient selection is removed '
      'only from Canvas-owned roots',
      () {
        final source = <String, dynamic>{
          'activeElementId': 'canvas-selection',
          'title': 'Canvas',
          'metadata': {
            'activeElementId': 'business-metadata',
            'nested': [
              {'value': 1},
            ],
          },
          'responsive': {
            'version': 2,
            'mobile': {
              'activeElementId': 'mobile-selection',
              'title': 'Canvas móvil',
              'layout': {
                'rows': [
                  {'x': 1},
                ],
              },
            },
          },
        };

        final sanitized = sanitizeWebsiteBlockDataForPersistence(
          blockType: 'canvas',
          data: source,
        );
        final mobile =
            (sanitized['responsive'] as Map)['mobile'] as Map<dynamic, dynamic>;

        expect(sanitized.containsKey('activeElementId'), isFalse);
        expect(mobile.containsKey('activeElementId'), isFalse);
        expect(
          (sanitized['metadata'] as Map)['activeElementId'],
          'business-metadata',
        );

        ((source['metadata'] as Map)['nested'] as List).first['value'] = 99;
        ((((source['responsive'] as Map)['mobile'] as Map)['layout']
                as Map)['rows'] as List)
            .first['x'] = 99;

        expect(
          ((sanitized['metadata'] as Map)['nested'] as List).first['value'],
          1,
        );
        expect(
          (((mobile['layout'] as Map)['rows'] as List).first as Map)['x'],
          1,
        );
      },
    );

    test(
      'Carousel strips responsive selection per slide but preserves root data',
      () {
        final sanitized = sanitizeWebsiteBlockDataForPersistence(
          blockType: 'carousel',
          data: const <String, dynamic>{
            'activeElementId': 'carousel-domain-value',
            'slides': [
              {
                'activeElementId': 'slide-selection',
                'title': 'Slide',
                'responsive': {
                  'version': 2,
                  'mobile': {
                    'activeElementId': 'mobile-slide-selection',
                    'title': 'Slide móvil',
                  },
                },
                'metadata': {'activeElementId': 'slide-domain-value'},
              },
            ],
          },
        );

        expect(sanitized['activeElementId'], 'carousel-domain-value');
        final slide = (sanitized['slides'] as List).single as Map;
        expect(slide.containsKey('activeElementId'), isFalse);
        expect(
          (((slide['responsive'] as Map)['mobile']) as Map)
              .containsKey('activeElementId'),
          isFalse,
        );
        expect(
          (slide['metadata'] as Map)['activeElementId'],
          'slide-domain-value',
        );
      },
    );
  });
}

List<Map<String, dynamic>> _legacySelectionBlocks() {
  return <Map<String, dynamic>>[
    {
      'id': 'canvas-1',
      'block_type': 'canvas',
      'block_data': {
        'activeElementId': 'legacy-canvas-selection',
        'title': 'Canvas persisted title',
        'metadata': {
          'activeElementId': 'nested-canvas-value',
          'keep': true,
        },
        'elements': [
          {
            ..._canvasElement('canvas-first'),
            'activeElementId': 'element-owned-value',
          },
        ],
      },
      'sort_order': 0,
      'is_visible': true,
    },
    {
      'id': 'carousel-1',
      'block_type': 'carousel',
      'block_data': {
        'activeElementId': 'carousel-root-domain-value',
        'autoplay': false,
        'slides': [
          {
            ..._carouselSlide(
              id: 'slide-first',
              elementId: 'slide-first-element',
              activeElementId: 'legacy-slide-selection',
            ),
            'metadata': {
              'activeElementId': 'nested-slide-value',
              'keep': true,
            },
            'elements': [
              {
                ..._canvasElement('slide-first-element'),
                'activeElementId': 'slide-element-owned-value',
              },
            ],
          },
        ],
      },
      'sort_order': 1,
      'is_visible': true,
    },
    {
      'id': 'about-1',
      'block_type': 'about',
      'block_data': {
        'activeElementId': 'about-domain-value',
        'title': 'About',
      },
      'sort_order': 2,
      'is_visible': true,
    },
  ];
}

List<Map<String, dynamic>> _cleanLifecycleBlocks() {
  return <Map<String, dynamic>>[
    {
      'id': 'canvas-1',
      'block_type': 'canvas',
      'block_data': {
        'title': 'Canvas',
        'elements': [
          _canvasElement('canvas-first'),
          _canvasElement('canvas-second'),
        ],
      },
      'sort_order': 0,
      'is_visible': true,
    },
    {
      'id': 'carousel-1',
      'block_type': 'carousel',
      'block_data': {
        'autoplay': false,
        'slides': [
          _carouselSlide(
            id: 'slide-first',
            elementId: 'slide-first-element',
          ),
          _carouselSlide(
            id: 'slide-second',
            elementId: 'slide-second-element',
          ),
        ],
      },
      'sort_order': 1,
      'is_visible': true,
    },
  ];
}

Map<String, dynamic> _canvasElement(String id) {
  return <String, dynamic>{
    'id': id,
    'type': 'text',
    'text': 'Layer $id',
    'x': 10.0,
    'y': 20.0,
    'w': 200.0,
    'h': 80.0,
  };
}

Map<String, dynamic> _carouselSlide({
  required String id,
  required String elementId,
  String? activeElementId,
}) {
  return <String, dynamic>{
    'id': id,
    'title': 'Persisted slide',
    'useComposition': true,
    'elements': [_canvasElement(elementId)],
    if (activeElementId != null) 'activeElementId': activeElementId,
  };
}

List<Map<String, dynamic>> _withLegacySelectionMetadata(
  List<Map<String, dynamic>> blocks,
) {
  return blocks.map((block) {
    final copy = _copyMap(block);
    final type = (copy['block_type'] ?? copy['type']).toString();
    final data = Map<String, dynamic>.from(copy['block_data'] as Map);
    if (type == 'canvas') {
      data['activeElementId'] = 'legacy-rpc-canvas-selection';
    } else if (type == 'carousel') {
      final slides = (data['slides'] as List).map((slide) {
        return <String, dynamic>{
          ...Map<String, dynamic>.from(slide as Map),
          'activeElementId': 'legacy-rpc-slide-selection',
        };
      }).toList(growable: false);
      data['slides'] = slides;
    }
    copy['block_data'] = data;
    return copy;
  }).toList(growable: false);
}

Map<String, dynamic> _dataFor(
  List<Map<String, dynamic>> blocks,
  String blockId,
) {
  final block = blocks.singleWhere((candidate) => candidate['id'] == blockId);
  return Map<String, dynamic>.from(block['block_data'] as Map);
}

void _expectTransientSelectionAbsent(List<Map<String, dynamic>> blocks) {
  final canvas = _dataFor(blocks, 'canvas-1');
  expect(canvas.containsKey('activeElementId'), isFalse);

  final carousel = _dataFor(blocks, 'carousel-1');
  final slides = carousel['slides'] as List;
  for (final slide in slides.whereType<Map>()) {
    expect(
      slide.containsKey('activeElementId'),
      isFalse,
      reason: 'Carousel slide selection must never enter document history.',
    );
  }
}

Map<String, dynamic> _copyMap(Map<String, dynamic> source) {
  return source.map(
    (key, value) => MapEntry(key, _copyValue(value)),
  );
}

dynamic _copyValue(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _copyValue(nested)),
    );
  }
  if (value is List) return value.map(_copyValue).toList(growable: false);
  return value;
}
