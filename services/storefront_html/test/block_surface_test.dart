import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_storefront_html/src/block_surface.dart';

void main() {
  BlockSurface surface(
    WebsiteBlockType type,
    Map<String, dynamic> data, [
    WebsiteViewport viewport = WebsiteViewport.desktop,
  ]) => BlockSurface(type, data, viewport);

  test('a section band takes all four sides once one is set', () {
    final band = surface(WebsiteBlockType.faq, {
      'style': {'paddingTop': 16},
    });
    expect(band.paddingVars, [
      '--sp-t:16px',
      '--sp-r:24px',
      '--sp-b:64px',
      '--sp-l:24px',
    ]);
    expect(band.wraps, isFalse);
    final phone = surface(WebsiteBlockType.services, {
      'style': {'paddingTop': 16},
    }, WebsiteViewport.mobile);
    expect(phone.paddingVars, [
      '--sp-t:16px',
      '--sp-r:16px',
      '--sp-b:56px',
      '--sp-l:16px',
    ]);
  });

  test('another family takes only the sides set; a header or a row inset '
      'gives way at a side set', () {
    expect(
      surface(WebsiteBlockType.about, {
        'style': {'paddingLeft': 40},
      }).paddingVars,
      ['--sp-l:40px'],
    );
    final grid = surface(WebsiteBlockType.categoryGrid, {
      'style': {'paddingLeft': 8},
    });
    expect(grid.paddingVars, ['--sp-l:8px', '--sp-lx:0px']);
  });

  test(
    'a family padded around its content takes the padding on the wrapper',
    () {
      final text = surface(WebsiteBlockType.text, {
        'style': {'paddingTop': 32, 'backgroundColor': '#FFEEDD'},
      });
      expect(text.wraps, isTrue);
      expect(text.paddingVars, isEmpty);
      expect(text.wrapperStyle, 'background:rgb(255 238 221);padding-top:32px');
      expect(
        surface(WebsiteBlockType.divider, {
          'responsive': {
            'mobile': {'surfacePaddingTop': 12},
          },
        }, WebsiteViewport.mobile).wrapperStyle,
        'padding-top:12px',
      );
    },
  );

  test('a gradient goes as the editor names its direction; a video banner '
      'is not clipped to its corners', () {
    expect(
      surface(WebsiteBlockType.videoBanner, {
        'style': {
          'backgroundType': 'gradient',
          'gradientDirection': 'to-bottom-right',
          'borderRadius': 10,
        },
      }).wrapperStyle,
      'background:linear-gradient(to bottom right,rgb(255 255 255),'
      'rgb(245 245 245));border-radius:10px',
    );
  });

  test('a canvas and the footer have no surface; a call to action knows '
      'when a side was set', () {
    final canvas = surface(WebsiteBlockType.canvas, {
      'style': {'backgroundColor': '#000000', 'paddingTop': 20},
    });
    expect(canvas.wraps, isFalse);
    expect(canvas.ownsBackground, isFalse);
    expect(canvas.paddingVars, isEmpty);
    expect(canvas.hasPadding, isFalse);
    final cta = surface(WebsiteBlockType.cta, {
      'blockHeight': 420,
      'style': {'paddingTop': 20},
    });
    expect(cta.hasPadding, isTrue);
    expect(cta.paddingVars, ['--sp-t:20px']);
    expect(
      surface(WebsiteBlockType.cta, {'blockHeight': 420}).hasPadding,
      isFalse,
    );
  });
}
