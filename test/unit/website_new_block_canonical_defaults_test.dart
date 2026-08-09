import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

void main() {
  test('registry creates Hero and Canvas in canonical responsive form', () {
    final hero = WebsiteBlockRegistry.definitionFor(
      WebsiteBlockType.hero,
    ).defaultData;
    expect(hero['focalPointX'], 0.5);
    expect(hero['focalPointY'], 0.5);
    expect(hero, isNot(contains('mobileFocalPointX')));
    expect(hero, isNot(contains('mobileFocalPointY')));

    for (final viewport in WebsiteViewport.values) {
      final projected = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: hero,
        viewport: viewport,
      );
      expect(projected['focalPointX'], 0.5, reason: viewport.name);
      expect(projected['focalPointY'], 0.5, reason: viewport.name);
    }

    final canvas = WebsiteBlockRegistry.definitionFor(
      WebsiteBlockType.canvas,
    ).defaultData;
    expect(
      canvas[WebsiteCanvasResponsiveDocument.schemaVersionKey],
      WebsiteCanvasResponsiveDocument.schemaVersion,
    );
    expect(canvas, isNot(contains('mobileFocalPointX')));
    expect(canvas, isNot(contains('mobileFocalPointY')));
    expect(
      WebsiteCanvasMigration.inspect(canvas).state,
      WebsiteCanvasMigrationState.canonical,
    );
  });

  test('provider addBlock never introduces a legacy or migration-needed block',
      () {
    for (final type in <WebsiteBlockType>[
      WebsiteBlockType.hero,
      WebsiteBlockType.canvas,
    ]) {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[],
          const <String, dynamic>{},
          pageId: 'page-1',
          pageSlug: '/inicio',
        )
        ..addBlock(type.name);
      addTearDown(provider.dispose);

      final block = provider.blocks.single;
      final data = Map<String, dynamic>.from(block['block_data'] as Map);
      expect(data, isNot(contains('mobileFocalPointX')), reason: type.name);
      expect(data, isNot(contains('mobileFocalPointY')), reason: type.name);
      if (type == WebsiteBlockType.canvas) {
        expect(
          provider.canvasMigrationStatus(block['id'] as String)!.state,
          WebsiteCanvasMigrationState.canonical,
        );
      }
    }
  });
}
