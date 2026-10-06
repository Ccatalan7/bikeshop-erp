import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_surface_presence.dart';

void main() {
  test('the HTML storefront knows every key of the surface the editor saves',
      () {
    // The HTML storefront does not paint surfaces yet: a block with one is
    // left to Flutter. A key the editor adds without telling the core would
    // let a page lose its background in HTML.
    expect(
      websiteBlockSurfaceMapKeys,
      {
        for (final field in [
          ...WebsiteBlockSurfaceFields.paddingFields,
          ...WebsiteBlockSurfaceFields.sharedFields,
        ])
          WebsiteBlockSurfaceFields.legacyKey(field),
      },
    );
  });

  test('a surface is the style map, the button-safe map or a phone padding',
      () {
    expect(websiteBlockHasAuthoredSurface({'text': 'Hola'}), isFalse);
    // A button's scalar style is its variant.
    expect(websiteBlockHasAuthoredSurface({'style': 'filled'}), isFalse);
    expect(
      websiteBlockHasAuthoredSurface({
        'style': {'backgroundColor': '#112233'},
      }),
      isTrue,
    );
    expect(
      websiteBlockHasAuthoredSurface({
        'style': 'outline',
        'surfaceStyle': {'borderWidth': 1},
      }),
      isTrue,
    );
    // A removed property is not a surface.
    expect(
      websiteBlockHasAuthoredSurface({
        'style': {'backgroundColor': null},
      }),
      isFalse,
    );
    expect(
      websiteBlockHasAuthoredSurface({
        'responsive': {
          'version': 1,
          'mobile': {'surfacePaddingTop': 16},
        },
      }),
      isTrue,
    );
    expect(
      websiteBlockHasAuthoredSurface({
        'responsive': {
          'mobile': {'surfacePaddingTop': null, 'title': 'Corto'},
        },
      }),
      isFalse,
    );
  });

  test('what the app decodes as authored, the core sees as a surface', () {
    for (final data in <Map<String, dynamic>>[
      {
        'style': {'paddingTop': 40},
      },
      {
        'surfaceStyle': {'shadowEnabled': true},
      },
      {
        'style': {'borderRadius': 10},
      },
    ]) {
      final style = WebsiteBlockSurfaceStyle.forLogicalWidth(
        data: data,
        logicalWidth: 1440,
      );
      expect(
        style.hasAuthoredPadding || style.hasAuthoredDecoration,
        isTrue,
        reason: '$data',
      );
      expect(websiteBlockHasAuthoredSurface(data), isTrue, reason: '$data');
    }
  });
}
