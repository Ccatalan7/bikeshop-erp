import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

void main() {
  const blockId = 'style-block';

  WebsiteEditModeProvider providerFor(Map<String, dynamic> data) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': blockId,
            'block_type': 'button',
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
        pageId: 'style-page',
        pageSlug: '/style',
      )
      ..selectBlock(blockId)
      ..setDevicePreviewMode(DevicePreviewMode.mobile)
      ..reportRenderedBlockViewport(blockId, WebsiteViewport.mobile);
    addTearDown(provider.dispose);
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  WebsiteInlineManipulationTarget targetFor(Map<String, dynamic> data) =>
      WebsiteInlineManipulationTarget(
        blockId: blockId,
        owner: const WebsiteInlineBlockOwner(),
        viewport: WebsiteViewport.mobile,
        properties: <WebsiteInlineManipulationProperty>[
          WebsiteInlineManipulationProperty(
            canonicalKey: WebsiteBlockSurfaceFields.baseMapKey(data),
            policy: WebsiteResponsivePropertyPolicy.sharedOnly,
          ),
        ],
      );

  test('one Style gesture is one undo and preserves Button scalar style', () {
    final provider = providerFor(<String, dynamic>{
      'style': 'filled',
      'surfaceStyle': <String, dynamic>{
        'borderRadius': 4,
        'futureOwner': <String, dynamic>{'v': 1},
      },
    });
    final before = dataOf(provider);
    final lease = provider.beginInlineManipulation(targetFor(before));
    expect(lease, isNotNull);

    // Arbitrarily many local slider ticks happen without touching provider.
    for (final draft in <double>[8, 16, 24, 32]) {
      expect(draft, isPositive);
      expect(dataOf(provider), before);
      expect(provider.canUndo, isFalse);
    }

    final source = Map<String, dynamic>.from(
      lease!.sourceBlock['block_data'] as Map,
    );
    final wholeMap = WebsiteBlockSurfaceFields.sharedMapWithValues(
      data: source,
      values: const {
        WebsiteBlockSurfaceFields.borderRadius: 32.0,
      },
    );
    expect(
      provider.commitInlineManipulation(
        lease,
        <String, Object?>{'surfaceStyle': wholeMap},
      ),
      isTrue,
    );

    final changed = dataOf(provider);
    expect(changed['style'], 'filled');
    expect((changed['surfaceStyle'] as Map)['borderRadius'], 32.0);
    expect(
      (changed['surfaceStyle'] as Map)['futureOwner'],
      <String, dynamic>{'v': 1},
    );
    expect(provider.canUndo, isTrue);

    provider.undo();
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);
  });

  test('stale Style lease fails closed instead of replacing a newer map', () {
    final provider = providerFor(<String, dynamic>{
      'style': <String, dynamic>{'borderRadius': 4},
    });
    final before = dataOf(provider);
    final lease = provider.beginInlineManipulation(targetFor(before));
    expect(lease, isNotNull);

    provider.updateBlockData(
      blockId,
      'style',
      <String, dynamic>{'borderRadius': 20, 'newerOwner': true},
    );
    final staleMap = WebsiteBlockSurfaceFields.sharedMapWithValues(
      data: before,
      values: const {
        WebsiteBlockSurfaceFields.borderRadius: 48.0,
      },
    );

    expect(
      provider.commitInlineManipulation(
        lease!,
        <String, Object?>{'style': staleMap},
      ),
      isFalse,
    );
    expect(
      dataOf(provider)['style'],
      <String, dynamic>{'borderRadius': 20, 'newerOwner': true},
    );
  });
}
