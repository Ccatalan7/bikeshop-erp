import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_canvas_manipulation.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

const _blockId = 'block-1';

WebsiteEditModeProvider _provider({String pageId = 'page-a'}) {
  return WebsiteEditModeProvider()
    ..enterEditMode(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _blockId,
          'block_type': 'hero',
          'block_data': <String, dynamic>{'title': 'Uno'},
          'is_visible': true,
          'sort_order': 0,
        },
      ],
      const <String, dynamic>{},
      pageId: pageId,
      pageSlug: '/inicio',
    )
    ..selectBlock(_blockId);
}

void main() {
  test('async intent is one-shot and admits one synchronous mutation', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final intent = provider.captureAsyncIntent(blockId: _blockId);
    expect(intent, isNotNull);

    expect(
      provider.commitAsyncIntent(intent!, () {
        provider.updateBlockData(_blockId, 'title', 'Dos');
        return WebsiteInlineMutationResult.committed;
      }),
      WebsiteInlineMutationResult.committed,
    );
    expect(provider.getBlockData(_blockId)['title'], 'Dos');
    expect(provider.canUndo, isTrue);

    expect(
      provider.commitAsyncIntent(
        intent,
        () => WebsiteInlineMutationResult.committed,
      ),
      WebsiteInlineMutationResult.rejected,
    );
  });

  test('page source ABA rejects without dirtying the restored document', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final intent = provider.captureAsyncIntent(blockId: _blockId);
    expect(intent, isNotNull);

    provider.updateBlockData(_blockId, 'title', 'Dos');
    provider.undo();
    expect(provider.getBlockData(_blockId)['title'], 'Uno');
    expect(provider.hasUnsavedChanges, isFalse);

    expect(
      provider.commitAsyncIntent(
        intent!,
        () {
          provider.deleteBlock(_blockId);
          return WebsiteInlineMutationResult.committed;
        },
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(provider.getBlock(_blockId), isNotNull);
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('scope and selection ABA reject an old async result', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    provider.setDevicePreviewMode(DevicePreviewMode.mobile);
    expect(provider.previewViewport, WebsiteViewport.mobile);
    expect(provider.writeScope, WebsiteWriteScope.shared);
    final scopeIntent = provider.captureAsyncIntent(blockId: _blockId);
    provider.setWriteScope(WebsiteWriteScope.viewport);
    expect(provider.writeScope, WebsiteWriteScope.viewport);
    provider.setWriteScope(WebsiteWriteScope.shared);

    expect(
      provider.commitAsyncIntent(
        scopeIntent!,
        () => WebsiteInlineMutationResult.committed,
      ),
      WebsiteInlineMutationResult.rejected,
    );

    final selectionIntent = provider.captureAsyncIntent(blockId: _blockId);
    provider.selectBlock(null);
    provider.selectBlock(_blockId);
    expect(
      provider.commitAsyncIntent(
        selectionIntent!,
        () => WebsiteInlineMutationResult.committed,
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('intent from another provider is rejected even with identical bytes',
      () {
    final providerA = _provider();
    final providerB = _provider();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    final intent = providerA.captureAsyncIntent(blockId: _blockId);

    expect(
      providerB.commitAsyncIntent(
        intent!,
        () {
          providerB.deleteBlock(_blockId);
          return WebsiteInlineMutationResult.committed;
        },
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(providerB.getBlock(_blockId), isNotNull);
    expect(providerB.hasUnsavedChanges, isFalse);
  });

  test('empty-page insertion intent needs no selected block', () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        pageId: 'empty',
        pageSlug: '/empty',
      );
    addTearDown(provider.dispose);
    final intent = provider.captureAsyncIntent(requiresSelection: false);

    expect(intent, isNotNull);
    expect(
      provider.commitAsyncIntent(intent!, () {
        provider.addBlock('hero', atIndex: 0);
        return WebsiteInlineMutationResult.committed;
      }),
      WebsiteInlineMutationResult.committed,
    );
    expect(provider.blocks, hasLength(1));
    expect(provider.canUndo, isTrue);
  });

  test('Canvas field-scope and rendered-viewport ABA reject old intent', () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'canvas-block',
            'block_type': 'canvas',
            'block_data': <String, dynamic>{
              'canvasResponsiveVersion': 2,
              'designWidth': 1200.0,
              'blockHeight': 480.0,
              'responsive': <String, dynamic>{'version': 2},
              'elements': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'layer-a',
                  'type': 'text',
                  'x': 10.0,
                  'y': 20.0,
                  'w': 120.0,
                  'h': 48.0,
                  'text': 'A',
                },
              ],
            },
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
        pageId: 'canvas-page',
        pageSlug: '/canvas',
      )
      ..selectBlock('canvas-block')
      ..setDevicePreviewMode(DevicePreviewMode.mobile);
    addTearDown(provider.dispose);
    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-block');
    provider.reportRenderedCanvasSize(
      document,
      const Size(390, 480),
      expectedMeasurementGeneration:
          provider.renderedCanvasMeasurementGeneration,
    );
    final scopeKey = provider.canvasFieldScopeKey(
      blockId: 'canvas-block',
      layerId: 'layer-a',
      propertyKey: 'x',
      viewport: WebsiteViewport.mobile,
    );
    final scopeIntent = provider.captureAsyncIntent(blockId: 'canvas-block');

    provider.setCanvasFieldScope(
      scopeKey,
      WebsiteWriteScope.viewport,
      policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      viewport: WebsiteViewport.mobile,
    );
    provider.setCanvasFieldScope(
      scopeKey,
      WebsiteWriteScope.shared,
      policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      viewport: WebsiteViewport.mobile,
    );
    expect(
      provider.commitAsyncIntent(
        scopeIntent!,
        () => WebsiteInlineMutationResult.committed,
      ),
      WebsiteInlineMutationResult.rejected,
    );

    final viewportIntent = provider.captureAsyncIntent(blockId: 'canvas-block');
    provider.reportRenderedCanvasSize(
      document,
      const Size(834, 480),
      expectedMeasurementGeneration:
          provider.renderedCanvasMeasurementGeneration,
    );
    provider.reportRenderedCanvasSize(
      document,
      const Size(390, 480),
      expectedMeasurementGeneration:
          provider.renderedCanvasMeasurementGeneration,
    );
    expect(
      provider.commitAsyncIntent(
        viewportIntent!,
        () => WebsiteInlineMutationResult.committed,
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
  });
}
