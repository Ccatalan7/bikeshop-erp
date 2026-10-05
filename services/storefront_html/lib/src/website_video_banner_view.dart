import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_hero_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'css_values.dart';
import 'website_blocks_view.dart';

/// What the HTML video banner draws: a YouTube or uploaded video (or the
/// photo) behind the words, on the block's own dark color.
bool videoBannerIsCovered(Map<String, dynamic> data) {
  final style = data['style'];
  return style is! Map || style.isEmpty;
}

/// `_VideoBannerWidget`: the video muted and looping behind a darkening
/// veil (the photo when there is no video), the title, the subtitle in
/// italics and the button, centered at most 800 px wide. 500 px tall unless
/// the page gives it a height.
class VideoBannerView extends StatelessComponent {
  const VideoBannerView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final title = (data['title'] ?? '').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final image = data['imageUrl']?.toString().trim() ?? '';
    final videoUrl = data['videoUrl']?.toString().trim() ?? '';
    final file = data['videoFileUrl']?.toString().trim() ?? '';
    final youtube = videoUrl.isEmpty ? null : websiteYouTubeVideoId(videoUrl);
    final action = WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: const ['ctaText', 'buttonText', 'label'],
      hrefKeys: const ['ctaLink', 'buttonLink', 'link'],
      defaultLabel: (data['ctaText'] ?? 'Ver más').toString().trim(),
      defaultHref: (data['ctaLink'] ?? '/productos').toString().trim(),
      defaultVariant: WebsiteActionVariant.outline,
      enabled: data['showCta'] != false,
    );
    final href = action == null || action.label.isEmpty
        ? null
        : context.publicHref(action.href);
    final opacity = (numberValue(data['overlayOpacity']) ?? 0.5).clamp(
      0.0,
      1.0,
    );
    final fx = (numberValue(data['focalPointX']) ?? 0.5).clamp(0.0, 1.0);
    final fy = (numberValue(data['focalPointY']) ?? 0.5).clamp(0.0, 1.0);
    const black = WebsiteRgba(1, 0, 0, 0);
    final playsVideo = youtube != null || file.isNotEmpty;
    return section(
      classes: [
        'vb',
        if (composed.block.geometry.exactHeight != null) 'fixed',
      ].join(' '),
      [
        if (youtube != null)
          div(classes: 'vb-media', [
            Component.element(
              tag: 'iframe',
              attributes: {
                'src':
                    'https://www.youtube.com/embed/$youtube?autoplay=1&mute=1'
                    '&loop=1&playlist=$youtube&controls=0&showinfo=0&rel=0'
                    '&modestbranding=1&playsinline=1&enablejsapi=1'
                    '&origin=${Uri.encodeQueryComponent(context.storeUrl)}',
                'title': title.isEmpty ? 'Video' : title,
                'allow': 'autoplay; encrypted-media',
                'loading': 'lazy',
                'tabindex': '-1',
                'aria-hidden': 'true',
              },
            ),
          ])
        else if (file.isNotEmpty)
          div(classes: 'vb-media', [
            Component.element(
              tag: 'video',
              attributes: {
                'src': file,
                'autoplay': '',
                'muted': '',
                'loop': '',
                'playsinline': '',
                'preload': 'metadata',
                'aria-hidden': 'true',
              },
            ),
          ])
        else if (image.isNotEmpty && !playsVideo)
          img(
            classes: 'vb-img',
            src: image,
            alt: '',
            loading: MediaLoading.lazy,
            attributes: {
              'style':
                  'object-position:${cssNum(fx * 100)}% ${cssNum(fy * 100)}%',
            },
          ),
        div(
          classes: 'vb-ov',
          attributes: {
            'style':
                'background:linear-gradient(${black.withAlpha(opacity * 0.3).css},'
                '${black.withAlpha(opacity).css})',
          },
          const [],
        ),
        div(classes: 'vb-in', [
          if (title.isNotEmpty) h2(classes: 'vb-t', [.text(title)]),
          if (subtitle.isNotEmpty) p(classes: 'vb-s', [.text(subtitle)]),
          if (action != null && href != null)
            a(
              classes: 'w-btn on-dark ${action.variant.storageValue}',
              href: href,
              [.text(action.label)],
            ),
        ]),
      ],
    );
  }
}

/// The banner's stylesheet. The YouTube frame covers the block the way
/// Flutter's does: at least 16:9 of the window, centered, and inert.
const videoBannerCss = '''
.vb{position:relative;height:500px;overflow:hidden;background:#1a1a1a}
.vb.fixed{height:100%}
.vb-media{position:absolute;inset:0;overflow:hidden;pointer-events:none}
.vb-media iframe{position:absolute;top:50%;left:50%;width:100%;height:100%;min-width:177.78vh;min-height:56.25vw;border:0;translate:-50% -50%;pointer-events:none}
.vb-media video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.vb-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.vb-ov{position:absolute;inset:0;pointer-events:none}
.vb-in{position:relative;display:flex;flex-direction:column;align-items:center;justify-content:center;max-width:800px;height:100%;margin:0 auto;padding:24px;text-align:center}
.vb-t{margin:0;font:400 40px/46px var(--head);letter-spacing:2px;color:#fff;-webkit-text-stroke:.032em currentColor}
.vb-s{margin:16px 0 0;font:italic 600 18px/23px var(--body);color:rgb(255 255 255 / .702)}
/* No text style of its own: the theme button's spacing (Material's .1). */
.vb-in .w-btn{margin-top:32px;letter-spacing:.1px}
''';
