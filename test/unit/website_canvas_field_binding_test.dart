import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_field_binding.dart';

/// 7B-3A — the reusable Canvas field authority.
///
/// One binding serves the block root and a layer, standalone or inside a
/// slide. It reads the projection, writes the atomic commands, and keeps the
/// "Personalizar" attribution transient and per field.

Map<String, dynamic> _document() => <String, dynamic>{
      'canvasResponsiveVersion': 2,
      'blockHeight': 480.0,
      'designWidth': 1200.0,
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'layer-a',
          'type': 'text',
          'x': 100.0,
          'y': 40.0,
          'w': 240.0,
          'h': 72.0,
          'text': 'Capa A',
          'responsive': <String, dynamic>{
            'version': 2,
            'tablet': <String, dynamic>{'x': 700.0},
          },
        },
        <String, dynamic>{
          'id': 'layer-b',
          'type': 'text',
          'x': 300.0,
          'y': 140.0,
          'w': 240.0,
          'h': 72.0,
          'text': 'Capa B',
        },
      ],
    };

Map<String, dynamic> _canvasBlock() => <String, dynamic>{
      'id': 'canvas-block',
      'block_type': 'canvas',
      'order_index': 0,
      'is_visible': true,
      'block_data': _document(),
    };

Map<String, dynamic> _carouselBlock() => <String, dynamic>{
      'id': 'carousel-block',
      'block_type': 'carousel',
      'order_index': 0,
      'is_visible': true,
      'block_data': <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{'useComposition': true, ..._document()},
          <String, dynamic>{'useComposition': true, ..._document()},
        ],
      },
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

WebsiteCanvasFieldBinding<num>? _numberField(
  WebsiteEditModeProvider provider, {
  required String blockId,
  String? layerId,
  int? slideIndex,
  String propertyKey = 'x',
}) {
  return WebsiteCanvasFieldBinding.resolve<num>(
    provider: provider,
    blockId: blockId,
    propertyKey: propertyKey,
    label: propertyKey,
    slideIndex: slideIndex,
    layerId: layerId,
    decode: (raw) => raw is num ? raw : null,
  );
}

Map<String, dynamic> _layerById(
  WebsiteEditModeProvider provider,
  String id, {
  int? slideIndex,
}) {
  final document = provider.canvasDocument(
    provider.blocks.first['id'] as String,
    slideIndex: slideIndex,
  )!;
  return Map<String, dynamic>.from(
    (document['elements'] as List)
        .firstWhere((element) => (element as Map)['id'] == id) as Map,
  );
}

void main() {
  test('the visible value is the projection, not the raw base', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);

    provider.setDevicePreviewMode(DevicePreviewMode.tablet);
    final tablet =
        _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!;
    expect(tablet.value, 700.0, reason: 'the tablet override is what shows');
    expect(tablet.state.status, WebsiteResponsiveFieldStatus.overridden);

    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    final mobile =
        _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!;
    expect(mobile.value, 100.0, reason: 'the phone inherits the base');
    expect(mobile.state.status, WebsiteResponsiveFieldStatus.inherited);
  });

  test('customize writes only the canonical branch and reset returns', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);
    final before = jsonEncode(provider.blocks);

    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .customize();
    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'attribution is transient: it must not touch the document',
    );
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);

    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .write(55.0);

    final layer = _layerById(provider, 'layer-a');
    expect(layer['x'], 100.0, reason: 'the base is untouched');
    expect(
        (layer['responsive'] as Map)['mobile'], <String, dynamic>{'x': 55.0});
    expect(
        (layer['responsive'] as Map)['tablet'], <String, dynamic>{'x': 700.0},
        reason: 'the tablet branch is untouched');
    expect(_layerById(provider, 'layer-b')['x'], 300.0,
        reason: 'a sibling layer is untouched');
    expect(provider.canUndo, isTrue);

    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .reset();
    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'reset returns to deep equality',
    );
  });

  test('the transient scope is per field, not global', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);

    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .customize();

    final other = _numberField(
      provider,
      blockId: 'canvas-block',
      layerId: 'layer-a',
      propertyKey: 'y',
    )!;
    expect(
      other.state.effectiveWriteScope,
      WebsiteWriteScope.shared,
      reason: 'promoting x must not promote the next write of y',
    );

    final sibling = _numberField(
      provider,
      blockId: 'canvas-block',
      layerId: 'layer-b',
    )!;
    expect(sibling.state.effectiveWriteScope, WebsiteWriteScope.shared);
  });

  test('desktop always writes the shared base', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);

    final field =
        _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!;
    field.customize();
    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .write(12.0);

    final layer = _layerById(provider, 'layer-a');
    expect(layer['x'], 12.0);
    expect(
      (layer['responsive'] as Map).containsKey('mobile'),
      isFalse,
      reason: 'desktop can never own a viewport branch',
    );
  });

  test('a paired write is one transaction and one undo', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);

    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .writeMany(<String, Object?>{'x': 11.0, 'y': 22.0});

    final layer = _layerById(provider, 'layer-a');
    expect(layer['x'], 11.0);
    expect(layer['y'], 22.0);
    expect(notifications, 1, reason: 'x and y are one change');
    provider.undo();
    expect(provider.canUndo, isFalse);
  });

  test('a nested slide field touches only that slide', () {
    final provider = _provider(<Map<String, dynamic>>[_carouselBlock()]);
    addTearDown(provider.dispose);
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);

    final field = _numberField(
      provider,
      blockId: 'carousel-block',
      layerId: 'layer-a',
      slideIndex: 1,
    )!;
    expect(field.value, 100.0);
    field.customize();
    _numberField(
      provider,
      blockId: 'carousel-block',
      layerId: 'layer-a',
      slideIndex: 1,
    )!
        .write(77.0);

    expect(
      (_layerById(provider, 'layer-a', slideIndex: 1)['responsive']
          as Map)['mobile'],
      <String, dynamic>{'x': 77.0},
    );
    expect(
      _layerById(provider, 'layer-a', slideIndex: 0)['responsive'],
      <String, dynamic>{
        'version': 2,
        'tablet': <String, dynamic>{'x': 700.0},
      },
      reason: 'the sibling slide is untouched',
    );
  });

  test('the editor default is inherited and an explicit shared wins', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    provider.setWriteScope(WebsiteWriteScope.viewport);

    expect(
      _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
          .state
          .effectiveWriteScope,
      WebsiteWriteScope.viewport,
      reason: 'a field with no choice of its own follows the editor default',
    );

    final field =
        _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!;
    provider.setCanvasFieldScope(
      field.scopeKey,
      WebsiteWriteScope.shared,
      policy: field.state.schema.responsivePolicy,
    );
    expect(
      _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
          .state
          .effectiveWriteScope,
      WebsiteWriteScope.shared,
      reason: 'an explicit shared must survive a global viewport default',
    );
  });

  test('promoting on the phone does not reach the tablet', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);

    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .customize();

    provider.setDevicePreviewMode(DevicePreviewMode.tablet);
    expect(
      _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
          .state
          .effectiveWriteScope,
      WebsiteWriteScope.shared,
      reason: 'the phone intention must not leak into the tablet',
    );

    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    expect(
      _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
          .state
          .effectiveWriteScope,
      WebsiteWriteScope.viewport,
      reason: 'returning to the phone keeps only the phone intention',
    );
  });

  test('leaving the document clears the transient scopes', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
        .customize();

    // Discarding the draft is the same lifecycle boundary that clears the
    // schema-field attributions.
    provider.discardPendingChanges();
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);

    expect(
      _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!
          .state
          .effectiveWriteScope,
      WebsiteWriteScope.shared,
      reason: 'a new session must not inherit the previous intention',
    );
  });

  test('customize then write on the SAME instance lands in the override', () {
    final provider = _provider(<Map<String, dynamic>>[_canvasBlock()]);
    addTearDown(provider.dispose);
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);

    final binding =
        _numberField(provider, blockId: 'canvas-block', layerId: 'layer-a')!;
    binding.customize();
    binding.write(66.0);

    final layer = _layerById(provider, 'layer-a');
    expect(layer['x'], 100.0, reason: 'the base is untouched');
    expect(
      (layer['responsive'] as Map)['mobile'],
      <String, dynamic>{'x': 66.0},
      reason: 'the scope must be resolved at write time, not captured',
    );
  });

  test('a legacy value stays readable but is not mutable yet', () {
    final legacy = _document();
    (legacy['elements'] as List)[1] = <String, dynamic>{
      'id': 'layer-b',
      'type': 'text',
      'x': 300.0,
      'y': 140.0,
      'w': 240.0,
      'h': 72.0,
      'hideOnMobile': true,
    };
    final provider = _provider(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'canvas-block',
        'block_type': 'canvas',
        'order_index': 0,
        'is_visible': true,
        'block_data': legacy,
      },
    ]);
    addTearDown(provider.dispose);
    final before = jsonEncode(provider.blocks);

    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    final visible = WebsiteCanvasFieldBinding.resolve<bool>(
      provider: provider,
      blockId: 'canvas-block',
      layerId: 'layer-b',
      propertyKey: 'visible',
      label: 'Visible',
      decode: (raw) => raw is bool ? raw : null,
    )!;

    expect(visible.isLegacyValue, isTrue);
    expect(
      visible.value,
      isFalse,
      reason: 'hideOnMobile true means the phone really does not show it',
    );
    expect(
      visible.state.status,
      WebsiteResponsiveFieldStatus.unavailable,
      reason: 'the ambiguous mutation is blocked, not resolved by guesswork',
    );
    visible.write(true);
    visible.reset();
    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'reading legacy must never migrate or rewrite it',
    );
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('every field of a legacy twin layer is blocked, not just visibility',
      () {
    final twins = _document();
    twins['elements'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'hero_desktop',
        'type': 'text',
        'x': 100.0,
        'y': 40.0,
        'w': 240.0,
        'h': 72.0,
        'text': 'Hero',
        'showOnMobile': false,
      },
      <String, dynamic>{
        'id': 'hero_mobile',
        'type': 'text',
        'x': 10.0,
        'y': 20.0,
        'w': 200.0,
        'h': 60.0,
        'text': 'Hero',
        'showOnMobile': true,
      },
    ];
    final provider = _provider(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'canvas-block',
        'block_type': 'canvas',
        'order_index': 0,
        'is_visible': true,
        'block_data': twins,
      },
    ]);
    addTearDown(provider.dispose);
    final before = jsonEncode(provider.blocks);
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);

    for (final id in <String>['hero_desktop', 'hero_mobile']) {
      final geometry = _numberField(
        provider,
        blockId: 'canvas-block',
        layerId: id,
      )!;
      expect(
        geometry.isLegacyValue,
        isTrue,
        reason: '$id reaches every value through the twin',
      );
      expect(
        geometry.state.status,
        WebsiteResponsiveFieldStatus.unavailable,
        reason: 'a twin layer cannot take an unambiguous per-viewport write',
      );
      geometry.write(999.0);
      geometry.reset();
    }

    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'inspecting a twin must never migrate or rewrite it',
    );
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
  });
}
