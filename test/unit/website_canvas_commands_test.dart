import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

/// 7B-2A — the single atomic command layer for a Canvas document.
///
/// The same API addresses a standalone Canvas block and a Canvas inside a
/// carousel slide. Each command is one transaction: one document, one
/// notification, one history entry — and a refused write leaves no trace.

Map<String, dynamic> _layer(
  String id, {
  double x = 100,
  double y = 40,
  Map<String, dynamic>? responsive,
}) {
  return <String, dynamic>{
    'id': id,
    'type': 'text',
    'x': x,
    'y': y,
    'w': 240.0,
    'h': 72.0,
    'text': 'Capa $id',
    if (responsive != null) 'responsive': responsive,
  };
}

/// The Canvas document both hosts start from.
Map<String, dynamic> _document() => <String, dynamic>{
      'canvasResponsiveVersion': 2,
      'blockHeight': 480.0,
      'designWidth': 1200.0,
      'showGrid': false,
      'elements': <Map<String, dynamic>>[
        _layer('layer-a'),
        _layer('layer-b', x: 300, y: 140),
        _layer('layer-c', x: 500, y: 240),
      ],
    };

Map<String, dynamic> _canvasBlock(Map<String, dynamic> document) =>
    <String, dynamic>{
      'id': 'canvas-block',
      'block_type': 'canvas',
      'order_index': 0,
      'is_visible': true,
      'block_data': document,
    };

Map<String, dynamic> _carouselBlock(
  Map<String, dynamic> document, {
  bool composed = true,
  String blockType = 'carousel',
  String id = 'carousel-block',
}) =>
    <String, dynamic>{
      'id': id,
      'block_type': blockType,
      'order_index': 0,
      'is_visible': true,
      'block_data': <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          composed
              ? <String, dynamic>{'useComposition': true, ...document}
              : <String, dynamic>{
                  'title': 'Sólo una portada',
                  'imageUrl': 'https://example.test/a.png',
                },
        ],
      },
    };

/// A block of some OTHER type that happens to carry Canvas-looking JSON.
Map<String, dynamic> _foreignBlock(
  String blockType,
  Map<String, dynamic> blockData,
) =>
    <String, dynamic>{
      'id': 'foreign-block',
      'block_type': blockType,
      'order_index': 0,
      'is_visible': true,
      'block_data': blockData,
    };

WebsiteEditModeProvider _provider(List<Map<String, dynamic>> blocks) {
  return WebsiteEditModeProvider()
    ..enterEditMode(
      blocks,
      const <String, dynamic>{},
      pageId: 'canvas-page',
      pageSlug: 'canvas-page',
    );
}

/// The Canvas document currently held by the draft.
Map<String, dynamic> _read(
  WebsiteEditModeProvider provider, {
  required bool nested,
}) {
  final data = Map<String, dynamic>.from(
    provider.blocks.first['block_data'] as Map,
  );
  if (!nested) return data;
  final slides = data['slides'] as List;
  return Map<String, dynamic>.from(slides.first as Map);
}

/// Both hosts hold the same Canvas document; only the slide flag differs.
Map<String, dynamic> _comparable(Map<String, dynamic> document) =>
    Map<String, dynamic>.from(document)..remove('useComposition');

Map<String, dynamic> _layerById(Map<String, dynamic> document, String id) {
  final elements = document['elements'] as List;
  return Map<String, dynamic>.from(
    elements.firstWhere((element) => (element as Map)['id'] == id) as Map,
  );
}

/// A draft plus the evidence a rejection must not disturb: its exact bytes and
/// how many times listeners were notified.
class _Probe {
  _Probe(List<Map<String, dynamic>> blocks) : provider = _provider(blocks) {
    before = jsonEncode(provider.blocks);
    provider.addListener(_count);
  }

  final WebsiteEditModeProvider provider;
  late final String before;
  int notifications = 0;

  void _count() => notifications++;

  void dispose() {
    provider.removeListener(_count);
    provider.dispose();
  }
}

bool _containsActiveElementId(Object? value) {
  if (value is Map) {
    if (value.containsKey('activeElementId')) return true;
    return value.values.any(_containsActiveElementId);
  }
  if (value is Iterable) return value.any(_containsActiveElementId);
  return false;
}

void main() {
  group('standalone and nested run the same command', () {
    late WebsiteEditModeProvider standalone;
    late WebsiteEditModeProvider nested;

    setUp(() {
      standalone = _provider(<Map<String, dynamic>>[_canvasBlock(_document())]);
      nested = _provider(<Map<String, dynamic>>[_carouselBlock(_document())]);
    });

    tearDown(() {
      standalone.dispose();
      nested.dispose();
    });

    void expectSameDocument(String reason) {
      expect(
        _comparable(_read(nested, nested: true)),
        equals(_comparable(_read(standalone, nested: false))),
        reason: reason,
      );
    }

    test('root set-many and clear-many converge', () {
      for (final provider in <WebsiteEditModeProvider>[standalone, nested]) {
        final slideIndex = provider == nested ? 0 : null;
        expect(
          provider.setCanvasRootProperties(
            provider.blocks.first['id'] as String,
            <String, Object?>{'blockHeight': 640.0, 'backgroundFit': 'contain'},
            slideIndex: slideIndex,
            scope: WebsiteWriteScope.viewport,
            viewport: WebsiteViewport.mobile,
          ),
          isTrue,
        );
      }
      expectSameDocument('root set-many');

      for (final provider in <WebsiteEditModeProvider>[standalone, nested]) {
        expect(
          provider.clearCanvasRootOverrides(
            provider.blocks.first['id'] as String,
            const <String>['blockHeight'],
            slideIndex: provider == nested ? 0 : null,
            viewport: WebsiteViewport.mobile,
          ),
          isTrue,
        );
      }
      expectSameDocument('root clear-many');
    });

    test('layer set-many and clear-many converge', () {
      for (final provider in <WebsiteEditModeProvider>[standalone, nested]) {
        expect(
          provider.setCanvasLayerProperties(
            provider.blocks.first['id'] as String,
            'layer-b',
            <String, Object?>{'x': 12.0, 'y': 34.0},
            slideIndex: provider == nested ? 0 : null,
            scope: WebsiteWriteScope.viewport,
            viewport: WebsiteViewport.tablet,
          ),
          isTrue,
        );
      }
      expectSameDocument('layer set-many');

      for (final provider in <WebsiteEditModeProvider>[standalone, nested]) {
        expect(
          provider.clearCanvasLayerOverrides(
            provider.blocks.first['id'] as String,
            'layer-b',
            const <String>['x', 'y'],
            slideIndex: provider == nested ? 0 : null,
            viewport: WebsiteViewport.tablet,
          ),
          isTrue,
        );
      }
      expectSameDocument('layer clear-many');
    });
  });

  test('x and y land in one transaction with exactly one undo', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock(_document()),
    ]);
    addTearDown(provider.dispose);

    final before = jsonEncode(provider.blocks);
    expect(provider.canUndo, isFalse);

    expect(
      provider.setCanvasLayerProperties(
        'canvas-block',
        'layer-a',
        <String, Object?>{'x': 640.0, 'y': 320.0},
        scope: WebsiteWriteScope.shared,
        viewport: WebsiteViewport.desktop,
      ),
      isTrue,
    );

    final after = _layerById(_read(provider, nested: false), 'layer-a');
    expect(after['x'], 640.0);
    expect(after['y'], 320.0);
    expect(provider.hasUnsavedChanges, isTrue);
    expect(provider.canUndo, isTrue);

    final committed = jsonEncode(provider.blocks);

    provider.undo();
    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'one atomic write is one undo, restoring the exact document',
    );
    expect(
      provider.canUndo,
      isFalse,
      reason: 'the pair must not have created a second history entry',
    );

    provider.redo();
    expect(jsonEncode(provider.blocks), committed);
  });

  test('desktop coerces every write to shared', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock(_document()),
    ]);
    addTearDown(provider.dispose);

    expect(
      provider.setCanvasLayerProperties(
        'canvas-block',
        'layer-a',
        <String, Object?>{'x': 555.0},
        // The caller asks for a viewport write; desktop refuses to own one.
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.desktop,
      ),
      isTrue,
    );

    final layer = _layerById(_read(provider, nested: false), 'layer-a');
    expect(layer['x'], 555.0, reason: 'desktop writes the shared base');
    expect(layer.containsKey('responsive'), isFalse);

    expect(
      provider.setCanvasRootProperties(
        'canvas-block',
        <String, Object?>{'blockHeight': 700.0},
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.desktop,
      ),
      isTrue,
    );
    final document = _read(provider, nested: false);
    expect(document['blockHeight'], 700.0);
    expect(document.containsKey('responsive'), isFalse);
  });

  test('a viewport override isolates the base and a reset inherits again', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock(_document()),
    ]);
    addTearDown(provider.dispose);

    provider.setCanvasLayerProperties(
      'canvas-block',
      'layer-a',
      <String, Object?>{'x': 20.0},
      scope: WebsiteWriteScope.viewport,
      viewport: WebsiteViewport.mobile,
    );
    provider.setCanvasLayerProperties(
      'canvas-block',
      'layer-a',
      <String, Object?>{'x': 60.0},
      scope: WebsiteWriteScope.viewport,
      viewport: WebsiteViewport.tablet,
    );

    var layer = _layerById(_read(provider, nested: false), 'layer-a');
    expect(layer['x'], 100.0, reason: 'the shared base is untouched');
    final container = layer['responsive'] as Map;
    expect((container['mobile'] as Map)['x'], 20.0);
    expect((container['tablet'] as Map)['x'], 60.0);

    // Projection reads what the overrides declare, per viewport.
    for (final entry in <WebsiteViewport, double>{
      WebsiteViewport.mobile: 20.0,
      WebsiteViewport.tablet: 60.0,
      WebsiteViewport.desktop: 100.0,
    }.entries) {
      expect(
        WebsiteResponsiveDataCodec.resolve<num>(
          data: layer,
          propertyKey: 'x',
          viewport: entry.key,
          decode: (raw) => raw is num ? raw : 0,
        ).value,
        entry.value,
        reason: 'effective x at ${entry.key.name}',
      );
    }

    expect(
      provider.clearCanvasLayerOverrides(
        'canvas-block',
        'layer-a',
        const <String>['x'],
        viewport: WebsiteViewport.mobile,
      ),
      isTrue,
    );
    layer = _layerById(_read(provider, nested: false), 'layer-a');
    expect(
      WebsiteResponsiveDataCodec.resolve<num>(
        data: layer,
        propertyKey: 'x',
        viewport: WebsiteViewport.mobile,
        decode: (raw) => raw is num ? raw : 0,
      ).value,
      100.0,
      reason: 'a reset removes the exception and inherits the base again',
    );
    expect(
      ((layer['responsive'] as Map)['tablet'] as Map)['x'],
      60.0,
      reason: 'resetting mobile must not touch tablet',
    );
  });

  test('base reorder moves the list, viewport reorder writes an override', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock(_document()),
    ]);
    addTearDown(provider.dispose);

    expect(
      provider.reorderCanvasLayer(
        'canvas-block',
        'layer-a',
        2,
        scope: WebsiteWriteScope.shared,
        viewport: WebsiteViewport.desktop,
      ),
      isTrue,
    );
    var document = _read(provider, nested: false);
    expect(
      (document['elements'] as List)
          .map((element) => (element as Map)['id'])
          .toList(),
      <String>['layer-b', 'layer-c', 'layer-a'],
      reason: 'the base z-order is the position in the list',
    );
    expect(
      _layerById(document, 'layer-a').containsKey('responsive'),
      isFalse,
      reason: 'a base move must not create a second z-order authority',
    );

    expect(
      provider.reorderCanvasLayer(
        'canvas-block',
        'layer-a',
        0,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      ),
      isTrue,
    );
    document = _read(provider, nested: false);
    expect(
      (document['elements'] as List)
          .map((element) => (element as Map)['id'])
          .toList(),
      <String>['layer-b', 'layer-c', 'layer-a'],
      reason: 'a viewport move leaves the base list alone',
    );
    expect(
      ((_layerById(document, 'layer-a')['responsive'] as Map)['mobile']
          as Map)['order'],
      0,
      reason: 'the phone order is a typed exception',
    );
  });

  test('a whitespace-padded id is addressable by its canonical identity', () {
    final document = _document();
    (document['elements'] as List)[1] = _layer('  layer-w  ', x: 300, y: 140);
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock(document)]);
    addTearDown(provider.dispose);

    expect(
      provider.setCanvasLayerProperties(
        'canvas-block',
        'layer-w',
        <String, Object?>{'x': 777.0},
        scope: WebsiteWriteScope.shared,
        viewport: WebsiteViewport.desktop,
      ),
      isTrue,
      reason: 'the contract declares the trimmed id canonical, so addressing '
          'must use the same identity the validator does',
    );
    expect(_layerById(_read(provider, nested: false), '  layer-w  ')['x'], 777);
  });

  group('a refused command leaves no trace', () {
    /// Every rejection must preserve the exact bytes, the dirty flag, the
    /// history and the notification count.
    void expectNoTrace(
      _Probe probe, {
      required String reason,
    }) {
      expect(jsonEncode(probe.provider.blocks), probe.before,
          reason: '$reason — bytes');
      expect(probe.provider.hasUnsavedChanges, isFalse,
          reason: '$reason — dirty');
      expect(probe.provider.canUndo, isFalse, reason: '$reason — history');
      expect(probe.notifications, 0, reason: '$reason — notifications');
    }

    test('a value-identical write is a no-op', () {
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(_document())]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'canvas-block',
          'layer-a',
          <String, Object?>{'x': 100.0, 'y': 40.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expectNoTrace(probe, reason: 'value-identical write');
    });

    test('invalid geometry is refused atomically without owner traces', () {
      for (final values in <Map<String, Object?>>[
        <String, Object?>{'x': double.nan},
        <String, Object?>{'y': double.infinity},
        <String, Object?>{'rotation': double.negativeInfinity},
        <String, Object?>{'w': 0.0},
        <String, Object?>{'h': -1.0},
        <String, Object?>{'x': '10'},
        <String, Object?>{'x': 777.0, 'w': 0.0},
      ]) {
        final probe = _Probe(
          <Map<String, dynamic>>[_canvasBlock(_document())],
        );
        addTearDown(probe.dispose);

        expect(
          probe.provider.setCanvasLayerProperties(
            'canvas-block',
            'layer-a',
            values,
            scope: WebsiteWriteScope.shared,
            viewport: WebsiteViewport.desktop,
          ),
          isFalse,
          reason: '$values',
        );
        expectNoTrace(probe, reason: 'invalid geometry $values');
      }
    });

    test('an unknown id on a valid document is refused', () {
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(_document())]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'canvas-block',
          'layer-zzz',
          <String, Object?>{'x': 1.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
        reason: 'an unknown id is a violation, not a no-op',
      );
      expectNoTrace(probe, reason: 'unknown id');
    });

    test('addressing with a blank id is refused', () {
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(_document())]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'canvas-block',
          '   ',
          <String, Object?>{'x': 1.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expectNoTrace(probe, reason: 'blank address');
    });

    test('a layer whose own id is blank blocks every write', () {
      final broken = _document();
      (broken['elements'] as List)[2] = _layer('   ', x: 500, y: 240);
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(broken)]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'canvas-block',
          'layer-a',
          <String, Object?>{'x': 1.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
        reason: 'an unusable identity anywhere makes the list unaddressable',
      );
      expectNoTrace(probe, reason: 'blank layer id');
    });

    test('a duplicated id names two layers and is refused', () {
      final ambiguous = _document();
      // The duplicate only collides once both ids are trimmed, which is the
      // identity the contract validates.
      (ambiguous['elements'] as List).add(_layer(' layer-a ', x: 900));
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(ambiguous)]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'canvas-block',
          'layer-a',
          <String, Object?>{'x': 1.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expect(
        probe.provider.reorderCanvasLayer(
          'canvas-block',
          'layer-a',
          0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expectNoTrace(probe, reason: 'duplicated id');
    });

    test('a base z-order write is refused instead of persisted', () {
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(_document())]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'canvas-block',
          'layer-a',
          <String, Object?>{'order': 2},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expectNoTrace(probe, reason: 'base z-order write');
    });

    test('a standalone target of the wrong block type is refused', () {
      // Canvas-looking JSON on a block the registry does not call a Canvas.
      final probe = _Probe(<Map<String, dynamic>>[
        _foreignBlock('hero', _document()),
      ]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'foreign-block',
          'layer-a',
          <String, Object?>{'x': 1.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
        reason: 'a stray elements list must not make a hero writable',
      );
      expect(
        probe.provider.setCanvasRootProperties(
          'foreign-block',
          <String, Object?>{'blockHeight': 900.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expectNoTrace(probe, reason: 'wrong standalone type');
    });

    test('a carousel addressed without a slide index is refused', () {
      final probe = _Probe(<Map<String, dynamic>>[
        _carouselBlock(_document()),
      ]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'carousel-block',
          'layer-a',
          <String, Object?>{'x': 1.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
        reason: 'the carousel block_data is not itself a Canvas document',
      );
      expect(
        probe.provider.setCanvasRootProperties(
          'carousel-block',
          <String, Object?>{'blockHeight': 900.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
        reason: 'a root write has no layer list to trip over, so only the '
            'target gate can stop it landing on the carousel',
      );
      expectNoTrace(probe, reason: 'carousel without slideIndex');
    });

    test('a non-carousel block carrying slides is refused', () {
      final probe = _Probe(<Map<String, dynamic>>[
        _carouselBlock(_document(), blockType: 'gallery', id: 'foreign-block'),
      ]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'foreign-block',
          'layer-a',
          <String, Object?>{'x': 1.0},
          slideIndex: 0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
        reason: 'a slide index only addresses a carousel',
      );
      expectNoTrace(probe, reason: 'slides on a non-carousel block');
    });

    test('a slide that is not a composed Canvas is refused', () {
      final probe = _Probe(<Map<String, dynamic>>[
        _carouselBlock(_document(), composed: false),
      ]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasRootProperties(
          'carousel-block',
          <String, Object?>{'blockHeight': 900.0},
          slideIndex: 0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
        reason: 'an image slide owns no Canvas document',
      );
      expect(
        probe.provider.setCanvasLayerProperties(
          'carousel-block',
          'layer-a',
          <String, Object?>{'x': 1.0},
          slideIndex: 0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expectNoTrace(probe, reason: 'non-composed slide');
    });

    test('a slide index outside the carousel is refused', () {
      final probe = _Probe(<Map<String, dynamic>>[
        _carouselBlock(_document()),
      ]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.setCanvasLayerProperties(
          'carousel-block',
          'layer-a',
          <String, Object?>{'x': 1.0},
          slideIndex: 7,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expectNoTrace(probe, reason: 'slide index out of range');
    });
  });

  test('mobile background-removal metadata never touches base or tablet', () {
    final document = _document();
    (document['elements'] as List)[0] = <String, dynamic>{
      'id': 'layer-a',
      'type': 'image',
      'x': 100.0,
      'y': 40.0,
      'w': 240.0,
      'h': 72.0,
      'imageUrl': 'https://example.test/desktop.png',
      'backgroundRemovalActive': false,
      'responsive': <String, dynamic>{
        'version': 2,
        'mobile': <String, dynamic>{
          'imageUrl': 'https://example.test/phone.png',
        },
      },
    };
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock(document)]);
    addTearDown(provider.dispose);

    // Removing the background on the phone writes the result and its
    // provenance against the PHONE picture.
    expect(
      provider.setCanvasLayerProperties(
        'canvas-block',
        'layer-a',
        <String, Object?>{
          'imageUrl': 'https://example.test/phone-cut.png',
          'backgroundRemovalActive': true,
          'backgroundRemovalOriginalUrl': 'https://example.test/phone.png',
          'backgroundRemovalMethod': 'auto',
        },
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      ),
      isTrue,
    );

    final layer = _layerById(_read(provider, nested: false), 'layer-a');
    expect(
      layer['imageUrl'],
      'https://example.test/desktop.png',
      reason: 'the desktop picture is untouched',
    );
    expect(
      layer['backgroundRemovalActive'],
      false,
      reason: 'desktop provenance must not learn about the phone edit',
    );
    expect(
      layer.containsKey('backgroundRemovalOriginalUrl'),
      isFalse,
      reason: 'the restore target of desktop is not created by a phone edit',
    );

    final container = layer['responsive'] as Map;
    final mobile = container['mobile'] as Map;
    expect(mobile['imageUrl'], 'https://example.test/phone-cut.png');
    expect(mobile['backgroundRemovalActive'], true);
    expect(mobile['backgroundRemovalOriginalUrl'],
        'https://example.test/phone.png');
    expect(mobile['backgroundRemovalMethod'], 'auto');
    expect(
      container.containsKey('tablet'),
      isFalse,
      reason: 'a phone edit creates no tablet exception',
    );

    // Restoring on the phone clears only the phone exception.
    expect(
      provider.clearCanvasLayerOverrides(
        'canvas-block',
        'layer-a',
        const <String>[
          'imageUrl',
          'backgroundRemovalActive',
          'backgroundRemovalOriginalUrl',
          'backgroundRemovalMethod',
        ],
        viewport: WebsiteViewport.mobile,
      ),
      isTrue,
    );
    final restored = _layerById(_read(provider, nested: false), 'layer-a');
    expect(restored['imageUrl'], 'https://example.test/desktop.png');
    expect(restored['backgroundRemovalActive'], false);
    expect(restored.containsKey('responsive'), isFalse);
  });

  group('layer lifecycle', () {
    Map<String, dynamic> withOverrides() {
      final document = _document();
      (document['elements'] as List)[1] = _layer(
        'layer-b',
        x: 300,
        y: 140,
        responsive: <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{'x': 10.0, 'visible': false},
          'tablet': <String, dynamic>{'y': 90.0},
        },
      );
      return document;
    }

    test('insert, remove and duplicate converge standalone and nested', () {
      final standalone =
          _provider(<Map<String, dynamic>>[_canvasBlock(withOverrides())]);
      final nested =
          _provider(<Map<String, dynamic>>[_carouselBlock(withOverrides())]);
      addTearDown(standalone.dispose);
      addTearDown(nested.dispose);

      for (final provider in <WebsiteEditModeProvider>[standalone, nested]) {
        final slideIndex = provider == nested ? 0 : null;
        final blockId = provider.blocks.first['id'] as String;
        expect(
          provider.insertCanvasLayer(
            blockId,
            _layer('layer-new', x: 700, y: 300),
            slideIndex: slideIndex,
          ),
          isTrue,
        );
        expect(
          provider.duplicateCanvasLayer(
            blockId,
            'layer-b',
            'layer-b-copy',
            slideIndex: slideIndex,
          ),
          isTrue,
        );
        expect(
          provider.removeCanvasLayer(blockId, 'layer-c',
              slideIndex: slideIndex),
          isTrue,
        );
      }

      expect(
        _comparable(_read(nested, nested: true)),
        equals(_comparable(_read(standalone, nested: false))),
        reason: 'the same commands must produce the same document',
      );
    });

    test('duplicate deep-copies every override and offsets what exists', () {
      final provider =
          _provider(<Map<String, dynamic>>[_canvasBlock(withOverrides())]);
      addTearDown(provider.dispose);

      expect(
        provider.duplicateCanvasLayer('canvas-block', 'layer-b', 'copy-b'),
        isTrue,
      );
      final document = _read(provider, nested: false);
      final ids = (document['elements'] as List)
          .map((element) => (element as Map)['id'])
          .toList();
      expect(ids, <String>['layer-a', 'layer-b', 'copy-b', 'layer-c'],
          reason: 'the copy lands next to its source');

      final source = _layerById(document, 'layer-b');
      final copy = _layerById(document, 'copy-b');
      expect(source['x'], 300.0, reason: 'the original is untouched');
      expect(copy['x'], 320.0);
      expect(copy['y'], 160.0);

      final sourceContainer = source['responsive'] as Map;
      final copyContainer = copy['responsive'] as Map;
      expect((copyContainer['mobile'] as Map)['x'], 30.0,
          reason: 'an existing phone x is offset too');
      expect((copyContainer['mobile'] as Map)['visible'], false,
          reason: 'visibility travels with the copy');
      expect((copyContainer['tablet'] as Map)['y'], 110.0);
      expect(
        (copyContainer['tablet'] as Map).containsKey('x'),
        isFalse,
        reason: 'an override the source never had must not be invented',
      );
      expect(
        (sourceContainer['mobile'] as Map)['x'],
        10.0,
        reason: 'no aliasing: editing the copy never moved the source',
      );
    });

    test('remove deletes the whole identity, overrides included', () {
      final provider =
          _provider(<Map<String, dynamic>>[_canvasBlock(withOverrides())]);
      addTearDown(provider.dispose);

      expect(provider.removeCanvasLayer('canvas-block', 'layer-b'), isTrue);
      final document = _read(provider, nested: false);
      expect(
        (document['elements'] as List)
            .map((element) => (element as Map)['id'])
            .toList(),
        <String>['layer-a', 'layer-c'],
      );
      expect(
        jsonEncode(document).contains('layer-b'),
        isFalse,
        reason: 'no responsive branch of the identity may survive',
      );
    });

    test('each lifecycle command is exactly one undo', () {
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(_document())]);
      addTearDown(probe.dispose);
      final before = probe.before;

      expect(
        probe.provider.insertCanvasLayer('canvas-block', _layer('layer-new')),
        isTrue,
      );
      expect(probe.notifications, 1);
      expect(probe.provider.canUndo, isTrue);

      probe.provider.undo();
      expect(jsonEncode(probe.provider.blocks), before);
      expect(probe.provider.canUndo, isFalse);
      probe.provider.redo();
      expect(
        (_read(probe.provider, nested: false)['elements'] as List).length,
        4,
      );
    });

    test('a colliding, blank or unknown identity leaves no trace', () {
      final probe = _Probe(<Map<String, dynamic>>[_canvasBlock(_document())]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.insertCanvasLayer('canvas-block', _layer('layer-a')),
        isFalse,
        reason: 'a new layer needs a new identity',
      );
      expect(
        probe.provider.insertCanvasLayer('canvas-block', _layer('   ')),
        isFalse,
      );
      expect(
        probe.provider.removeCanvasLayer('canvas-block', 'layer-zzz'),
        isFalse,
      );
      expect(
        probe.provider
            .duplicateCanvasLayer('canvas-block', 'layer-a', 'layer-b'),
        isFalse,
        reason: 'the duplicate id already exists',
      );
      expect(
        probe.provider.removeCanvasLayer('carousel-nope', 'layer-a'),
        isFalse,
      );

      expect(jsonEncode(probe.provider.blocks), probe.before);
      expect(probe.provider.hasUnsavedChanges, isFalse);
      expect(probe.provider.canUndo, isFalse);
      expect(probe.notifications, 0);
    });

    test('nested lifecycle touches only the addressed slide', () {
      final block = _carouselBlock(_document());
      (block['block_data'] as Map)['slides'] = <Map<String, dynamic>>[
        (block['block_data'] as Map)['slides'][0] as Map<String, dynamic>,
        <String, dynamic>{'useComposition': true, ..._document()},
      ];
      final provider = _provider(<Map<String, dynamic>>[block]);
      addTearDown(provider.dispose);

      expect(
        provider.removeCanvasLayer('carousel-block', 'layer-a', slideIndex: 1),
        isTrue,
      );
      final slides =
          (provider.blocks.first['block_data'] as Map)['slides'] as List;
      expect(
        ((slides[0] as Map)['elements'] as List).length,
        3,
        reason: 'the untouched slide keeps its layers',
      );
      expect(((slides[1] as Map)['elements'] as List).length, 2);
    });

    test('"Agregar capa" inserts through the command, standalone and nested',
        () {
      for (final nested in <bool>[false, true]) {
        final probe = _Probe(<Map<String, dynamic>>[
          nested
              ? _carouselBlock(withOverrides())
              : _canvasBlock(withOverrides()),
        ]);
        final blockId = probe.provider.blocks.first['id'] as String;

        expect(
          probe.provider.addCanvasElementToCanvasBlock(blockId, 'text'),
          isTrue,
          reason: nested ? 'nested' : 'standalone',
        );

        final document = _read(probe.provider, nested: nested);
        final elements = document['elements'] as List;
        expect(elements.length, 4, reason: 'the layer landed');
        // The panel must not rebuild the list: the overrides of the layers it
        // did not touch have to survive intact.
        final untouched = _layerById(document, 'layer-b');
        expect((untouched['responsive'] as Map)['mobile'],
            <String, dynamic>{'x': 10.0, 'visible': false});
        expect((untouched['responsive'] as Map)['tablet'],
            <String, dynamic>{'y': 90.0});

        final newId = (elements.last as Map)['id'] as String;
        expect(
          probe.provider.canvasElementSelection(
            blockId,
            slideIndex: nested ? 0 : null,
          ),
          newId,
          reason: 'the new layer becomes selected',
        );

        // Exactly one persisted undo.
        expect(probe.notifications, greaterThanOrEqualTo(1));
        probe.provider.undo();
        expect(
          (_read(probe.provider, nested: nested)['elements'] as List).length,
          3,
        );
        expect(probe.provider.canUndo, isFalse);
        probe.dispose();
      }
    });

    test('"Agregar capa" on a wrong target leaves no trace', () {
      final probe = _Probe(<Map<String, dynamic>>[
        _foreignBlock('hero', _document()),
      ]);
      addTearDown(probe.dispose);

      expect(
        probe.provider.addCanvasElementToCanvasBlock('foreign-block', 'text'),
        isFalse,
      );
      expect(
        probe.provider.addCanvasElementToCanvasBlock('nope', 'text'),
        isFalse,
      );
      expect(jsonEncode(probe.provider.blocks), probe.before);
      expect(probe.provider.hasUnsavedChanges, isFalse);
      expect(probe.provider.canUndo, isFalse);
      expect(probe.notifications, 0);
      expect(probe.provider.canvasElementSelection('foreign-block'), isNull);
    });

    test('a fresh id never collides with an identity in the document', () {
      final document = _document();
      (document['elements'] as List).add(_layer('el_seed'));
      expect(
        WebsiteCanvasResponsiveDocument.nextLayerId(document, seed: 'el_seed'),
        isNot('el_seed'),
      );
      expect(
        WebsiteCanvasResponsiveDocument.nextLayerId(document, seed: 'el_free'),
        'el_free',
      );
    });
  });

  test('selection stays transient across a command', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock(_document()),
    ]);
    addTearDown(provider.dispose);

    provider.selectCanvasElement('canvas-block', 'layer-a');
    expect(provider.canvasElementSelection('canvas-block'), 'layer-a');

    expect(
      provider.setCanvasLayerProperties(
        'canvas-block',
        'layer-a',
        <String, Object?>{'x': 480.0},
        scope: WebsiteWriteScope.shared,
        viewport: WebsiteViewport.desktop,
      ),
      isTrue,
    );

    expect(
      provider.canvasElementSelection('canvas-block'),
      'layer-a',
      reason: 'a write must not drop the selection',
    );
    expect(
      _containsActiveElementId(provider.blocks),
      isFalse,
      reason: 'selection is never serialized into the document',
    );
  });

  test('canvasDocument is deeply immutable for standalone and nested owners',
      () {
    for (final nested in <bool>[false, true]) {
      final provider = _provider(<Map<String, dynamic>>[
        nested ? _carouselBlock(_document()) : _canvasBlock(_document()),
      ]);
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);
      final epoch = provider.pageDocumentEpoch;
      final document = provider.canvasDocument(
        nested ? 'carousel-block' : 'canvas-block',
        slideIndex: nested ? 0 : null,
      )!;
      final elements = document['elements'] as List;
      final layer = elements.first as Map;

      expect(
        () => elements.add(<String, dynamic>{'id': 'injected'}),
        throwsUnsupportedError,
      );
      expect(() => layer['x'] = 999.0, throwsUnsupportedError);
      expect(jsonEncode(provider.blocks), before);
      expect(provider.pageDocumentEpoch, epoch);
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
    }
  });
}
