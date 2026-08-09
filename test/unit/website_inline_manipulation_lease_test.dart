import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

const _blockId = 'block-1';

Map<String, dynamic> _blockData(WebsiteEditModeProvider provider) =>
    Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

WebsiteEditModeProvider _provider({
  Map<String, dynamic>? data,
  DevicePreviewMode preview = DevicePreviewMode.mobile,
}) {
  return WebsiteEditModeProvider()
    ..enterEditMode(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _blockId,
          'block_type': 'hero',
          'block_data': data ??
              <String, dynamic>{
                'title': 'Uno',
                'blockHeight': 500.0,
                'spacingAfter': 32.0,
              },
          'is_visible': true,
          'sort_order': 0,
        },
      ],
      const <String, dynamic>{},
      pageId: 'page-a',
      pageSlug: '/inicio',
    )
    ..selectBlock(_blockId)
    ..setDevicePreviewMode(preview);
}

WebsiteInlineManipulationTarget _target(
  WebsiteViewport viewport,
  WebsiteInlineManipulationProperty property, {
  bool requiresSelection = true,
}) {
  return WebsiteInlineManipulationTarget(
    blockId: _blockId,
    owner: const WebsiteInlineBlockOwner(),
    viewport: viewport,
    properties: <WebsiteInlineManipulationProperty>[property],
    requiresSelection: requiresSelection,
  );
}

final _titleProperty = WebsiteInlineManipulationProperty(
  canonicalKey: 'title',
  policy: WebsiteResponsivePropertyPolicy.sharedOnly,
);

void main() {
  test('first viewport report enables capture without document side effects',
      () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final target = _target(WebsiteViewport.mobile, _titleProperty);

    expect(provider.captureInlineMutationLease(target), isNull);
    final navigationRevision = provider.navigationStateRevision;
    final documentEpoch = provider.pageDocumentEpoch;
    var notifications = 0;
    provider.addListener(() => notifications++);

    provider.reportRenderedBlockViewport(
      _blockId,
      WebsiteViewport.mobile,
    );

    expect(notifications, 1);
    expect(provider.navigationStateRevision, navigationRevision);
    expect(provider.pageDocumentEpoch, documentEpoch);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(provider.captureInlineMutationLease(target), isNotNull);

    provider.reportRenderedBlockViewport(
      _blockId,
      WebsiteViewport.mobile,
    );
    expect(notifications, 1, reason: 'same geometry is not a new event');
  });

  test('responsive height commits to the rendered viewport in one undo', () {
    final provider = _provider(
      data: <String, dynamic>{
        'title': 'Uno',
        'blockHeight': 500.0,
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{'blockHeight': 300.0},
        },
      },
    );
    addTearDown(provider.dispose);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    provider.setFieldWriteScope(
      blockId: _blockId,
      propertyKey: WebsiteBlockMetaFields.blockHeight.key,
      policy: WebsiteBlockMetaFields.blockHeight.responsivePolicy,
      scope: WebsiteWriteScope.viewport,
      viewport: WebsiteViewport.mobile,
    );
    final target = _target(
      WebsiteViewport.mobile,
      WebsiteInlineManipulationProperty.fromSchema(
        WebsiteBlockMetaFields.blockHeight,
      ),
    );
    final lease = provider.beginInlineManipulation(target);

    expect(lease, isNotNull);
    expect(
      provider.commitInlineManipulation(
        lease!,
        <String, Object?>{'blockHeight': 360.0},
      ),
      isTrue,
    );
    var data = _blockData(provider);
    expect(data['blockHeight'], 500.0);
    expect(
      (data['responsive'] as Map)['mobile']['blockHeight'],
      360.0,
    );
    expect(provider.canUndo, isTrue);

    provider.undo();
    data = _blockData(provider);
    expect((data['responsive'] as Map)['mobile']['blockHeight'], 300.0);
    expect(provider.canUndo, isFalse);
  });

  test('cancel performs zero writes, dirty changes and history', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    final before = _blockData(provider);
    final lease = provider.beginInlineManipulation(
      _target(
        WebsiteViewport.mobile,
        WebsiteInlineManipulationProperty.fromSchema(
          WebsiteBlockMetaFields.spacingAfter,
        ),
        requiresSelection: false,
      ),
    );

    expect(lease, isNotNull);
    expect(provider.cancelInlineManipulation(lease!), isTrue);
    expect(_blockData(provider), before);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(
      provider.commitInlineManipulation(
        lease,
        <String, Object?>{'spacingAfter': 96.0},
      ),
      isFalse,
      reason: 'a cancelled one-shot lease cannot be resurrected',
    );
  });

  test('scope ABA rejects the old callback without history', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    final property = WebsiteInlineManipulationProperty.fromSchema(
      WebsiteBlockMetaFields.blockHeight,
    );
    final target = _target(WebsiteViewport.mobile, property);
    final lease = provider.captureInlineMutationLease(target);
    expect(lease, isNotNull);

    provider.setFieldWriteScope(
      blockId: _blockId,
      propertyKey: property.canonicalKey,
      policy: property.policy,
      scope: WebsiteWriteScope.viewport,
      viewport: WebsiteViewport.mobile,
    );
    provider.setFieldWriteScope(
      blockId: _blockId,
      propertyKey: property.canonicalKey,
      policy: property.policy,
      scope: WebsiteWriteScope.shared,
      viewport: WebsiteViewport.mobile,
    );

    expect(
      provider.commitInlineMutation(
        lease!,
        <String, Object?>{'blockHeight': 640.0},
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(_blockData(provider)['blockHeight'], 500.0);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
  });

  test('discrete callback distinguishes unchanged and supports recapture', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    final target = _target(WebsiteViewport.mobile, _titleProperty);
    var lease = provider.captureInlineMutationLease(target);

    expect(
      provider.commitInlineMutation(
        lease!,
        <String, Object?>{'title': 'Uno'},
      ),
      WebsiteInlineMutationResult.unchanged,
    );
    expect(provider.canUndo, isFalse);
    lease = provider.captureInlineMutationLease(target);
    expect(lease, isNotNull);
  });

  test('three accepted writes recapture exact new source each time', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    final target = _target(WebsiteViewport.mobile, _titleProperty);

    for (final value in <String>['Dos', 'Tres', 'Cuatro']) {
      final lease = provider.captureInlineMutationLease(target);
      expect(lease, isNotNull);
      expect(
        provider.commitInlineMutation(
          lease!,
          <String, Object?>{'title': value},
        ),
        WebsiteInlineMutationResult.committed,
      );
    }
    expect(_blockData(provider)['title'], 'Cuatro');

    provider.undo();
    expect(_blockData(provider)['title'], 'Tres');
    provider.undo();
    expect(_blockData(provider)['title'], 'Dos');
    provider.undo();
    expect(_blockData(provider)['title'], 'Uno');
    expect(provider.canUndo, isFalse);
  });

  test('viewport ABA and source mutation both fail closed', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    final target = _target(WebsiteViewport.mobile, _titleProperty);
    final viewportLease = provider.captureInlineMutationLease(target);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.tablet);
    provider.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);

    expect(
      provider.commitInlineMutation(
        viewportLease!,
        <String, Object?>{'title': 'Stale'},
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(provider.canUndo, isFalse);

    final sourceLease = provider.captureInlineMutationLease(target);
    provider.updateBlockData(_blockId, 'title', 'Externo');
    expect(
      provider.commitInlineMutation(
        sourceLease!,
        <String, Object?>{'title': 'Stale'},
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(_blockData(provider)['title'], 'Externo');
    provider.undo();
    expect(provider.canUndo, isFalse);
  });

  test('lease from another provider is rejected with identical state', () {
    final providerA = _provider();
    final providerB = _provider();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    providerA.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    providerB.reportRenderedBlockViewport(_blockId, WebsiteViewport.mobile);
    final beforeA = _blockData(providerA);
    final beforeB = _blockData(providerB);
    final lease = providerA.captureInlineMutationLease(
      _target(WebsiteViewport.mobile, _titleProperty),
    );

    expect(lease, isNotNull);
    expect(
      providerB.commitInlineMutation(
        lease!,
        <String, Object?>{'title': 'Redirigido'},
      ),
      WebsiteInlineMutationResult.rejected,
    );
    expect(_blockData(providerA), beforeA);
    expect(_blockData(providerB), beforeB);
    expect(providerA.canUndo, isFalse);
    expect(providerB.canUndo, isFalse);
  });
}
