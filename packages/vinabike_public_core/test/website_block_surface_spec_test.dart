import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_surface_spec.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';

void main() {
  test('colors are read as the editor writes them', () {
    expect(websiteSurfaceColor('#0C2537')?.css, 'rgb(12 37 55)');
    expect(websiteSurfaceColor('#800C2537')?.css, 'rgb(12 37 55 / 0.502)');
    expect(
      websiteSurfaceColor('rgba(12,37,55,0.13)')?.css,
      'rgb(12 37 55 / 0.13)',
    );
    expect(websiteSurfaceColor('rgb(300, 0, 0)')?.css, 'rgb(255 0 0)');
    for (final raw in [null, '', 'red', '#12345', 'rgba(1,2)']) {
      expect(websiteSurfaceColor(raw), isNull, reason: '$raw');
    }
  });

  test('a block without a surface has nothing authored', () {
    final spec = WebsiteBlockSurfaceSpec.resolve(
      data: {'title': 'Hola', 'style': 'filled'},
      viewport: WebsiteViewport.desktop,
    );
    expect(spec.baseMapKey, 'surfaceStyle');
    expect(spec.hasAuthoredDecoration, isFalse);
    expect(spec.hasAuthoredPadding, isFalse);
    expect(spec.backgroundType, 'solid');
    expect(spec.shadowColor.css, 'rgb(12 37 55 / 0.13)');
  });

  test('the shared map and a phone override give the padding of a band', () {
    final data = {
      'style': {
        'paddingTop': 32,
        'backgroundColor': '#F5F5F5',
        'borderRadius': 99,
        'shadowEnabled': true,
        'shadowBlur': 22,
      },
      'responsive': {
        'mobile': {'surfacePaddingTop': 16, 'surfacePaddingLeft': 8},
      },
    };
    final desktop = WebsiteBlockSurfaceSpec.resolve(
      data: data,
      viewport: WebsiteViewport.desktop,
    );
    expect(desktop.isPaddingAuthored(WebsiteSurfaceSide.top), isTrue);
    expect(desktop.isPaddingAuthored(WebsiteSurfaceSide.left), isFalse);
    expect(
      desktop.paddingWithFallback(
        websiteBlockSurfaceDefaultPadding(
          blockType: WebsiteBlockType.faq,
          viewport: WebsiteViewport.desktop,
          data: data,
        ),
      ),
      const WebsiteSurfaceInsets(top: 32, right: 24, bottom: 64, left: 24),
    );
    expect(desktop.borderRadius, 50);
    expect(desktop.hasAuthoredBackground, isTrue);
    expect(desktop.backgroundColor?.css, 'rgb(245 245 245)');

    final phone = WebsiteBlockSurfaceSpec.resolve(
      data: data,
      viewport: WebsiteViewport.mobile,
    );
    expect(
      phone.paddingWithFallback(
        websiteBlockSurfaceDefaultPadding(
          blockType: WebsiteBlockType.faq,
          viewport: WebsiteViewport.mobile,
          data: data,
        ),
      ),
      const WebsiteSurfaceInsets(top: 16, right: 16, bottom: 64, left: 8),
    );
    expect(phone.isPaddingAuthored(WebsiteSurfaceSide.left), isTrue);
  });

  test('a call to action with a height of its own has no vertical default', () {
    expect(
      websiteBlockSurfaceDefaultPadding(
        blockType: WebsiteBlockType.cta,
        viewport: WebsiteViewport.tablet,
        data: {'blockHeight': 420},
      ),
      const WebsiteSurfaceInsets.symmetric(horizontal: 24),
    );
  });
}
