import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_public_visibility.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';

void main() {
  test('legacy visibility preserves 640/1024 at the two rollout canaries', () {
    const block = <String, dynamic>{
      'is_visible': true,
      'block_data': {
        'visibility': {
          'desktop': true,
          'tablet': false,
          'mobile': true,
        },
      },
    };

    expect(
      websitePublicViewportForBlockDataWidth(
        block['block_data'] as Map<String, dynamic>,
        620,
      ),
      WebsiteViewport.mobile,
    );
    expect(isWebsiteBlockVisibleAtLogicalWidth(block, 620), isTrue);
    expect(
      websitePublicViewportForBlockDataWidth(
        block['block_data'] as Map<String, dynamic>,
        1000,
      ),
      WebsiteViewport.tablet,
    );
    expect(isWebsiteBlockVisibleAtLogicalWidth(block, 1000), isFalse);
  });

  test('unrelated canonical overrides do not migrate legacy visibility', () {
    const block = <String, dynamic>{
      'is_visible': true,
      'block_data': {
        'visibility': {
          'desktop': true,
          'tablet': false,
          'mobile': true,
        },
        'responsive': {
          'version': 2,
          'mobile': {'focalPointX': 0.7},
        },
      },
    };

    expect(
      websitePublicViewportForBlockDataWidth(
        block['block_data'] as Map<String, dynamic>,
        620,
      ),
      WebsiteViewport.mobile,
    );
    expect(isWebsiteBlockVisibleAtLogicalWidth(block, 620), isTrue);
    expect(
      websitePublicViewportForBlockDataWidth(
        block['block_data'] as Map<String, dynamic>,
        1000,
      ),
      WebsiteViewport.tablet,
    );
    expect(isWebsiteBlockVisibleAtLogicalWidth(block, 1000), isFalse);
  });

  test('an explicit visibility migration uses the canonical 600/900 bands', () {
    const block = <String, dynamic>{
      'is_visible': true,
      'block_data': {
        'visibility': {
          'version': 2,
          'desktop': true,
          'tablet': false,
          'mobile': true,
        },
      },
    };

    expect(
      websitePublicViewportForBlockDataWidth(
        block['block_data'] as Map<String, dynamic>,
        620,
      ),
      WebsiteViewport.tablet,
    );
    expect(isWebsiteBlockVisibleAtLogicalWidth(block, 620), isFalse);
    expect(
      websitePublicViewportForBlockDataWidth(
        block['block_data'] as Map<String, dynamic>,
        1000,
      ),
      WebsiteViewport.desktop,
    );
    expect(isWebsiteBlockVisibleAtLogicalWidth(block, 1000), isTrue);
  });

  test('global is_visible remains a hard public gate', () {
    const block = <String, dynamic>{
      'is_visible': false,
      'block_data': {
        'visibility': {
          'desktop': true,
          'tablet': true,
          'mobile': true,
        },
        'responsive': {
          'version': 2,
          'mobile': {'focalPointX': 0.7},
        },
      },
    };

    for (final width in const [390.0, 620.0, 1000.0, 1440.0]) {
      expect(isWebsiteBlockVisibleAtLogicalWidth(block, width), isFalse);
    }
  });
}
