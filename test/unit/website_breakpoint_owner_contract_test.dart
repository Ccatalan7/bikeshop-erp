import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storefront consumers use the semantic viewport owner', () {
    for (final path in <String>[
      'lib/public_store/pages/public_home_page.dart',
      'lib/public_store/pages/dynamic_website_page.dart',
      'lib/public_store/pages/static_policy_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('WebsiteViewport.fromLogicalWidth'));
      expect(source, contains('logicalWidth:'));
      expect(source, isNot(contains('if (width < 640)')));
      expect(source, isNot(contains('if (width < 1024)')));
      expect(source, isNot(contains('websitePublicBreakpointForWidth(')));
    }
  });

  test('convergence harnesses cannot invent a desktop threshold', () {
    for (final path in <String>[
      'test/widgets/website_renderer_convergence_test.dart',
      'test/widgets/website_canvas_renderer_convergence_test.dart',
      'test/widgets/website_canvas_responsive_render_test.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('WebsiteViewport.fromLogicalWidth'));
      expect(source, contains('logicalWidth:'));
      expect(source, isNot(contains('if (width < 1200)')));
    }
  });

  test('page projection and editable leases share the same viewport value', () {
    final composition = File('lib/public_store/widgets/page_composition.dart')
        .readAsStringSync();
    final editable =
        File('lib/modules/website/widgets/editable_block_renderer.dart')
            .readAsStringSync();
    final renderer =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();
    final surface =
        File('lib/modules/website/widgets/website_block_surface.dart')
            .readAsStringSync();

    expect(
      composition,
      contains('effectiveViewport: viewport'),
      reason: 'the projection owner must hand its exact viewport to Edit',
    );
    expect(
      editable,
      contains('final effectiveViewport = widget.effectiveViewport;'),
    );
    expect(
      editable,
      isNot(contains('MediaQuery.sizeOf(context).width')),
      reason: 'an editable consumer cannot classify the host a second time',
    );
    expect(
      editable,
      isNot(contains('viewportForDocumentWidth(')),
    );
    expect(renderer, contains('required WebsiteViewport effectiveViewport'));
    expect(renderer, contains('viewport: effectiveViewport'));
    for (final duplicateOwner in <String>[
      'LayoutBuilder',
      'MediaQuery',
      'forLogicalWidth',
      'viewportForDocumentWidth',
    ]) {
      expect(
        surface,
        isNot(contains(duplicateOwner)),
        reason: 'the surface consumes the viewport; it never classifies it',
      );
    }
  });

  test('render consumers never read flat focal aliases', () {
    const adapterFiles = <String>{
      // Canvas owns a separate document adapter; this file contains only the
      // migration-boundary comment naming the aliases.
      'lib/modules/website/widgets/canvas_block.dart',
    };
    final roots = <Directory>[
      Directory('lib/modules/website/widgets'),
      Directory('lib/public_store'),
    ];
    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (adapterFiles.contains(entity.path)) continue;
        final source = entity.readAsStringSync();
        expect(
          source,
          isNot(
            contains(
              RegExp(
                r'mobileFocalPointX|mobileFocalPointY|mobileBgAlignment',
              ),
            ),
          ),
          reason: '${entity.path} must consume focalPointX/Y after projection',
        );
      }
    }
  });
}
