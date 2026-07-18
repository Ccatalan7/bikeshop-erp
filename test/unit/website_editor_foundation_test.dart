import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

void main() {
  test('nested Canvas selection is transient and never dirties block data', () {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'canvas-1',
          'block_type': 'canvas',
          'block_data': {
            'elements': [
              {'id': 'image-1', 'type': 'image', 'imageUrl': 'image.png'},
            ],
          },
        },
      ],
      const {},
    );

    provider.selectCanvasElement('canvas-1', 'image-1');

    expect(provider.selectedBlockId, 'canvas-1');
    expect(provider.canvasElementSelection('canvas-1'), 'image-1');
    expect(provider.hasUnsavedChanges, isFalse);
    expect(
      (provider.blocks.single['block_data'] as Map)
          .containsKey('activeElementId'),
      isFalse,
    );
  });

  test('Canvas click-add keeps the new layer and selects it transiently', () {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'canvas-1',
          'block_type': 'canvas',
          'block_data': {
            'elements': [
              {'id': 'text-1', 'type': 'text', 'text': 'Existing'},
            ],
          },
        },
      ],
      const {},
    );
    provider.selectBlock('canvas-1');

    expect(provider.addCanvasElementToSelectedCanvas('image'), isTrue);

    final data = Map<String, dynamic>.from(
      provider.blocks.single['block_data'] as Map,
    );
    final elements = (data['elements'] as List).cast<Map>();
    expect(elements, hasLength(2));
    expect(elements.last['type'], 'image');
    expect(
      provider.canvasElementSelection('canvas-1'),
      elements.last['id'],
    );
    expect(data.containsKey('activeElementId'), isFalse);
    expect(provider.hasUnsavedChanges, isTrue);
  });

  test('Canvas click-add works inside the selected composed carousel slide',
      () {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'carousel-1',
          'block_type': 'carousel',
          'block_data': {
            'slides': [
              {
                'title': 'One',
                'useComposition': true,
                'elements': [
                  {'id': 'one', 'type': 'text', 'text': 'One'},
                ],
              },
              {
                'title': 'Two',
                'useComposition': true,
                'elements': [
                  {'id': 'two', 'type': 'text', 'text': 'Two'},
                ],
              },
            ],
          },
        },
      ],
      const {},
    );
    provider.selectCarouselSlide('carousel-1', 1, 2);

    expect(provider.addCanvasElementToSelectedCanvas('image'), isTrue);

    final data = Map<String, dynamic>.from(
      provider.blocks.single['block_data'] as Map,
    );
    final slides = (data['slides'] as List).cast<Map>();
    final firstElements = (slides.first['elements'] as List).cast<Map>();
    final secondElements = (slides.last['elements'] as List).cast<Map>();
    expect(firstElements, hasLength(1));
    expect(secondElements, hasLength(2));
    expect(secondElements.last['type'], 'image');
    expect(
      provider.canvasElementSelection('carousel-1', slideIndex: 1),
      secondElements.last['id'],
    );
    expect(slides.last.containsKey('activeElementId'), isFalse);
  });

  test('registered blocks are created from the canonical registry defaults',
      () {
    for (final type in WebsiteBlockType.values) {
      final provider = WebsiteEditModeProvider();
      provider.enterEditMode(const [], const {});

      provider.addBlock(type.name);

      final data = Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );
      expect(
        data,
        equals(WebsiteBlockRegistry.definitionFor(type).defaultData),
        reason: '${type.name} must not use provider-local defaults',
      );
    }
  });
}
