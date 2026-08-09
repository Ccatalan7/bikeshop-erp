import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_canvas_manipulation.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_editor_binding.dart';

Map<String, dynamic> _layer(
  String id, {
  String type = 'text',
  bool locked = false,
  bool hiddenOnMobile = false,
}) =>
    <String, dynamic>{
      'id': id,
      'type': type,
      'x': 10.0,
      'y': 10.0,
      'w': 100.0,
      'h': 50.0,
      if (locked) 'locked': true,
      if (hiddenOnMobile)
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{'visible': false},
        },
    };

Map<String, dynamic> _canvasBlock(
  String blockId,
  List<Map<String, dynamic>> layers,
) =>
    <String, dynamic>{
      'id': blockId,
      'block_type': 'canvas',
      'block_data': <String, dynamic>{
        'canvasResponsiveVersion': 2,
        'elements': layers,
      },
      'is_visible': true,
    };

Map<String, dynamic> _carouselBlock(
  String blockId,
  List<List<Map<String, dynamic>>> slides,
) =>
    <String, dynamic>{
      'id': blockId,
      'block_type': 'carousel',
      'block_data': <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          for (final layers in slides)
            <String, dynamic>{
              'canvasResponsiveVersion': 2,
              'elements': layers,
            },
        ],
      },
      'is_visible': true,
    };

void _reportDocumentViewport(
  WebsiteEditModeProvider provider,
  WebsiteCanvasDocumentTarget document,
  WebsiteViewport viewport,
) {
  final width = switch (viewport) {
    WebsiteViewport.mobile => 390.0,
    WebsiteViewport.tablet => 834.0,
    WebsiteViewport.desktop => 1200.0,
  };
  provider.reportRenderedCanvasSize(
    document,
    Size(width, 500),
    expectedMeasurementGeneration: provider.renderedCanvasMeasurementGeneration,
  );
}

WebsiteEditModeProvider _provider(List<Map<String, dynamic>> blocks) {
  final provider = WebsiteEditModeProvider()
    ..enterEditMode(
      blocks,
      const <String, dynamic>{},
      pageId: 'page-a',
    );
  for (final block in blocks) {
    final blockId = block['id']?.toString();
    if (blockId == null || blockId.isEmpty) continue;
    final type = (block['block_type'] ?? block['type']).toString();
    if (type == 'canvas') {
      _reportDocumentViewport(
        provider,
        WebsiteCanvasDocumentTarget(blockId: blockId),
        WebsiteViewport.desktop,
      );
      continue;
    }
    if (type != 'carousel') continue;
    final data = block['block_data'];
    final slides = data is Map ? data['slides'] : null;
    if (slides is! List) continue;
    for (var index = 0; index < slides.length; index++) {
      _reportDocumentViewport(
        provider,
        WebsiteCanvasDocumentTarget(blockId: blockId, slideIndex: index),
        WebsiteViewport.desktop,
      );
    }
  }
  return provider;
}

bool _startSelected(
  WebsiteEditModeProvider provider,
  WebsiteCanvasManipulationMode mode,
) {
  final target = provider.selectedCanvasLayerTarget;
  if (target == null) return false;
  _reportDocumentViewport(provider, target.document, provider.previewViewport);
  return provider.startCanvasManipulation(
    mode,
    target: target,
    viewport: provider.renderedCanvasViewport(target.document)!,
  );
}

void main() {
  test('session requires one exact selected live layer', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock('canvas-a', <Map<String, dynamic>>[_layer('layer-a')]),
    ]);
    addTearDown(provider.dispose);

    provider.selectBlock('canvas-a');
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isFalse,
    );

    provider.selectCanvasElement('canvas-a', 'layer-a');
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isTrue,
    );
    expect(
      provider.canvasManipulationSession,
      const WebsiteCanvasManipulationSession(
        target: WebsiteCanvasLayerTarget(
          document: WebsiteCanvasDocumentTarget(blockId: 'canvas-a'),
          layerId: 'layer-a',
        ),
        mode: WebsiteCanvasManipulationMode.move,
        viewport: WebsiteViewport.desktop,
        generation: 1,
      ),
    );
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('same layer id in Canvas B cannot inherit Canvas A session', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock('canvas-a', <Map<String, dynamic>>[_layer('same-layer')]),
      _canvasBlock('canvas-b', <Map<String, dynamic>>[_layer('same-layer')]),
    ]);
    addTearDown(provider.dispose);

    provider.selectCanvasElement('canvas-a', 'same-layer');
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isTrue,
    );
    final sessionA = provider.canvasManipulationSession;
    expect(sessionA, isNotNull);

    const documentB = WebsiteCanvasDocumentTarget(blockId: 'canvas-b');
    final bindingB = WebsiteCanvasEditorBinding(
      documentTarget: documentB,
      activeElementId: 'same-layer',
      manipulationSession: sessionA,
      onActiveElementChanged: (_) {},
    );
    expect(
      bindingB.isManipulating(
        'same-layer',
        WebsiteCanvasManipulationMode.move,
        viewport: WebsiteViewport.desktop,
      ),
      isFalse,
    );

    provider.selectCanvasElement('canvas-b', 'same-layer');
    expect(provider.canvasManipulationSession, isNull);
    expect(
      provider.startCanvasManipulation(
        WebsiteCanvasManipulationMode.move,
        target: const WebsiteCanvasLayerTarget(
          document: WebsiteCanvasDocumentTarget(blockId: 'canvas-a'),
          layerId: 'same-layer',
        ),
        viewport: provider.previewViewport,
      ),
      isFalse,
    );
  });

  test('re-emitting the exact layer selection keeps the explicit mode armed',
      () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock('canvas-a', <Map<String, dynamic>>[_layer('layer-a')]),
    ]);
    addTearDown(provider.dispose);

    provider.selectCanvasElement('canvas-a', 'layer-a');
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isTrue,
    );
    final armed = provider.canvasManipulationSession;

    // CanvasBlock deliberately re-emits its selection after a completed
    // gesture so inspector focus can recover. That callback is not an exit.
    provider.selectCanvasElement('canvas-a', 'layer-a');
    expect(provider.canvasManipulationSession, armed);

    provider.selectCanvasElement('canvas-a', null);
    expect(provider.canvasManipulationSession, isNull);
  });

  test('stop then re-arm gets a new generation and stale commit fails closed',
      () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock('canvas-a', <Map<String, dynamic>>[_layer('layer-a')]),
    ]);
    addTearDown(provider.dispose);

    provider.selectCanvasElement('canvas-a', 'layer-a');
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isTrue,
    );
    final first = provider.canvasManipulationSession!;
    expect(provider.stopCanvasManipulation(expectedSession: first), isTrue);
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isTrue,
    );
    final second = provider.canvasManipulationSession!;
    final expectedDocument = provider.canvasDocument('canvas-a')!;
    final expectedDocumentEpoch = provider.pageDocumentEpoch;

    expect(second.generation, greaterThan(first.generation));
    expect(second, isNot(first));
    expect(
      provider.commitCanvasManipulation(
        first,
        expectedDocument,
        expectedDocumentEpoch,
        const <String, Object?>{'x': 20.0, 'y': 20.0},
        scope: WebsiteWriteScope.shared,
      ),
      isFalse,
    );
    expect(provider.hasPageDraftChanges, isFalse);
    expect(provider.canUndo, isFalse);

    expect(
      provider.commitCanvasManipulation(
        second,
        expectedDocument,
        expectedDocumentEpoch,
        const <String, Object?>{'x': 20.0, 'y': 20.0},
        scope: WebsiteWriteScope.shared,
      ),
      isTrue,
    );
    expect(provider.hasPageDraftChanges, isTrue);
    expect(provider.canUndo, isTrue);
  });

  test('slide switch invalidates an equal layer id at another index', () {
    final provider = _provider(<Map<String, dynamic>>[
      _carouselBlock('carousel-a', <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[_layer('same-layer')],
        <Map<String, dynamic>>[_layer('same-layer')],
      ]),
    ]);
    addTearDown(provider.dispose);

    provider.selectCanvasElement(
      'carousel-a',
      'same-layer',
      slideIndex: 0,
      slideCount: 2,
    );
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isTrue,
    );

    provider.selectCarouselSlide('carousel-a', 1, 2);
    expect(provider.canvasManipulationSession, isNull);
  });

  test('reselecting the active carousel slide is not an implicit exit', () {
    final provider = _provider(<Map<String, dynamic>>[
      _carouselBlock('carousel-a', <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[_layer('layer-a')],
        <Map<String, dynamic>>[_layer('layer-b')],
      ]),
    ]);
    addTearDown(provider.dispose);

    provider.selectCanvasElement(
      'carousel-a',
      'layer-a',
      slideIndex: 0,
      slideCount: 2,
    );
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.rotate),
      isTrue,
    );
    final armed = provider.canvasManipulationSession;

    provider.selectCarouselSlide('carousel-a', 0, 2);
    expect(provider.canvasManipulationSession, armed);

    provider.selectCarouselSlide('carousel-a', 1, 2);
    expect(provider.canvasManipulationSession, isNull);
  });

  test('inactive surfaces and viewport changes disarm the session', () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock('canvas-a', <Map<String, dynamic>>[_layer('layer-a')]),
    ]);
    addTearDown(provider.dispose);

    void arm() {
      provider.selectCanvasElement('canvas-a', 'layer-a');
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
    }

    arm();
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    expect(provider.canvasManipulationSession, isNull);

    arm();
    provider.openWorkspace(WebsiteWorkspaceMode.catalog);
    expect(provider.canvasManipulationSession, isNull);
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isFalse,
    );

    provider.returnToPageEditor();
    arm();
    provider.setMode(WebsiteEditorMode.preview);
    expect(provider.canvasManipulationSession, isNull);
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isFalse,
    );
  });

  test('hidden locked ambiguous and incompatible layers fail closed', () {
    final hiddenProvider = _provider(<Map<String, dynamic>>[
      _canvasBlock('hidden-canvas', <Map<String, dynamic>>[
        _layer('hidden', hiddenOnMobile: true),
      ]),
    ]);
    addTearDown(hiddenProvider.dispose);
    hiddenProvider
      ..setDevicePreviewMode(DevicePreviewMode.mobile)
      ..selectCanvasElement('hidden-canvas', 'hidden');
    _reportDocumentViewport(
      hiddenProvider,
      const WebsiteCanvasDocumentTarget(blockId: 'hidden-canvas'),
      WebsiteViewport.mobile,
    );
    expect(
      hiddenProvider
          .canvasManipulationAvailability(WebsiteCanvasManipulationMode.move)
          .reason,
      WebsiteCanvasManipulationBlockReason.layerHidden,
    );

    final lockedProvider = _provider(<Map<String, dynamic>>[
      _canvasBlock('locked-canvas', <Map<String, dynamic>>[
        _layer('locked', locked: true),
      ]),
    ]);
    addTearDown(lockedProvider.dispose);
    lockedProvider.selectCanvasElement('locked-canvas', 'locked');
    expect(
      lockedProvider
          .canvasManipulationAvailability(WebsiteCanvasManipulationMode.move)
          .reason,
      WebsiteCanvasManipulationBlockReason.layerLocked,
    );

    final duplicateProvider = _provider(<Map<String, dynamic>>[
      _canvasBlock('duplicate-canvas', <Map<String, dynamic>>[
        _layer('duplicate'),
        _layer('duplicate'),
      ]),
    ]);
    addTearDown(duplicateProvider.dispose);
    duplicateProvider.selectCanvasElement('duplicate-canvas', 'duplicate');
    expect(
      duplicateProvider
          .canvasManipulationAvailability(WebsiteCanvasManipulationMode.move)
          .reason,
      WebsiteCanvasManipulationBlockReason.layerAmbiguous,
    );

    final textProvider = _provider(<Map<String, dynamic>>[
      _canvasBlock('text-canvas', <Map<String, dynamic>>[_layer('text')]),
    ]);
    addTearDown(textProvider.dispose);
    textProvider.selectCanvasElement('text-canvas', 'text');
    expect(
      textProvider
          .canvasManipulationAvailability(WebsiteCanvasManipulationMode.crop)
          .reason,
      WebsiteCanvasManipulationBlockReason.modeUnsupported,
    );
  });

  test('structural slide replacement cannot retain an index-addressed session',
      () {
    final provider = _provider(<Map<String, dynamic>>[
      _carouselBlock('carousel-a', <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[_layer('layer-a')],
      ]),
    ]);
    addTearDown(provider.dispose);

    provider.selectCanvasElement(
      'carousel-a',
      'layer-a',
      slideIndex: 0,
      slideCount: 1,
    );
    expect(
      _startSelected(provider, WebsiteCanvasManipulationMode.move),
      isTrue,
    );

    provider.updateBlockData(
      'carousel-a',
      'slides',
      <Map<String, dynamic>>[
        <String, dynamic>{
          'canvasResponsiveVersion': 2,
          'elements': <Map<String, dynamic>>[_layer('layer-a')],
        },
      ],
    );
    expect(provider.canvasManipulationSession, isNull);
  });

  test('rendered Canvas size owns the effective touch viewport', () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          _canvasBlock('canvas-a', <Map<String, dynamic>>[_layer('layer-a')]),
        ],
        const <String, dynamic>{},
        pageId: 'page-a',
      );
    addTearDown(provider.dispose);

    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: document,
      layerId: 'layer-a',
    );
    provider.selectCanvasElement('canvas-a', 'layer-a');

    expect(provider.previewViewport, WebsiteViewport.desktop);
    expect(provider.renderedCanvasViewport(document), isNull);
    final navigationRevisionBeforeReport = provider.navigationStateRevision;
    var layoutNotifications = 0;
    provider.addListener(() => layoutNotifications++);

    provider.reportRenderedCanvasSize(
      document,
      const Size(451, 300),
      expectedMeasurementGeneration:
          provider.renderedCanvasMeasurementGeneration,
    );

    expect(provider.renderedCanvasViewport(document), WebsiteViewport.mobile);
    expect(provider.navigationStateRevision, navigationRevisionBeforeReport);
    expect(layoutNotifications, 1);
    expect(provider.hasPageDraftChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(
      provider.startCanvasManipulation(
        WebsiteCanvasManipulationMode.move,
        target: target,
        viewport: provider.renderedCanvasViewport(document)!,
      ),
      isTrue,
    );
    expect(
      provider.canvasManipulationSession?.viewport,
      WebsiteViewport.mobile,
    );
  });

  test('crossing a rendered Canvas breakpoint invalidates its exact session',
      () {
    final provider = _provider(<Map<String, dynamic>>[
      _canvasBlock('canvas-a', <Map<String, dynamic>>[_layer('layer-a')]),
    ]);
    addTearDown(provider.dispose);

    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: document,
      layerId: 'layer-a',
    );
    provider
      ..selectCanvasElement('canvas-a', 'layer-a')
      ..reportRenderedCanvasSize(
        document,
        const Size(451, 300),
        expectedMeasurementGeneration:
            provider.renderedCanvasMeasurementGeneration,
      );
    expect(
      provider.startCanvasManipulation(
        WebsiteCanvasManipulationMode.move,
        target: target,
        viewport: WebsiteViewport.mobile,
      ),
      isTrue,
    );

    provider.reportRenderedCanvasSize(
      document,
      const Size(820, 300),
      expectedMeasurementGeneration:
          provider.renderedCanvasMeasurementGeneration,
    );

    expect(provider.renderedCanvasViewport(document), WebsiteViewport.tablet);
    expect(provider.canvasManipulationSession, isNull);
    expect(provider.hasPageDraftChanges, isFalse);
    expect(provider.canUndo, isFalse);
  });
}
