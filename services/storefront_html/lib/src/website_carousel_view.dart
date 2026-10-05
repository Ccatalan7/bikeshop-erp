import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_public_core/modules/website/models/website_hero_content.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'css_values.dart';
import 'material_icons.dart';
import 'website_blocks_view.dart';
import 'website_canvas_view.dart';

/// The slides of a carousel block.
List<Map<String, dynamic>> carouselSlides(Map<String, dynamic> data) => [
  if (data['slides'] case final List<Object?> slides)
    for (final slide in slides)
      if (slide is Map) Map<String, dynamic>.from(slide),
];

/// A slide drawn as layers (`websiteCarouselSlideUsesComposition`).
bool carouselSlideUsesComposition(Map<String, dynamic> slide) =>
    slide['useComposition'] == true ||
    (slide['elements'] is List && (slide['elements'] as List).isNotEmpty);

/// What the HTML carousel draws: photo and color slides, with or without
/// layers it covers. A video slide plays a YouTube or uploaded video the
/// storefront does not embed yet.
bool carouselIsCovered(Map<String, dynamic> data) {
  for (final slide in carouselSlides(data)) {
    if ((slide['videoUrl'] ?? '').toString().trim().isNotEmpty ||
        (slide['videoFileUrl'] ?? '').toString().trim().isNotEmpty) {
      return false;
    }
    if (carouselSlideUsesComposition(slide) &&
        !canvasDocumentIsCovered(_slideDocument(slide))) {
      return false;
    }
  }
  return true;
}

Map<String, dynamic> _slideDocument(Map<String, dynamic> slide) =>
    WebsiteCanvasResponsiveDocument.carouselAuthoringDocument(
      slide: slide,
      showGrid: false,
    );

/// `WebsiteCarouselBlockContent` for a visitor: every slide stacked, the
/// current one shown, a cross-fade between them; arrows at the sides and
/// dots at the bottom, or both in one row at the bottom of a phone. The
/// page script plays it (`data-car`); without it the first slide stays.
class CarouselBlockView extends StatelessComponent {
  const CarouselBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final slides = carouselSlides(data);
    if (slides.isEmpty) return div(const []);
    final autoPlay = (data['autoPlay'] ?? true) == true;
    final showIndicators = (data['showIndicators'] ?? true) == true;
    final showArrows = (data['showArrows'] ?? true) == true;
    final interval = math.max(
      1,
      (numberValue(data['intervalSeconds']) ?? 5).toInt(),
    );
    final duration = math.max(
      1,
      (numberValue(data['animationDurationMs'] ?? data['transitionDuration']) ??
              600)
          .toInt(),
    );
    final animation = switch (data['animation']?.toString().toLowerCase()) {
      'fade' => 'fade',
      'zoom' => 'zoom',
      _ => 'slide',
    };
    // The carousel is a phone's when its block reads phone data: under 640
    // for a legacy document, under 600 for a canonical one.
    final phoneWidth = WebsiteResponsiveDataCodec.usesCanonicalSchema(data)
        ? 600
        : 640;
    final many = slides.length > 1;
    return section(
      classes: [
        'car',
        'ph$phoneWidth',
        if (composed.block.geometry.exactHeight == null) 'auto',
      ].join(' '),
      attributes: {
        'data-car': '',
        'data-anim': animation,
        if (autoPlay && many) 'data-interval': '${interval * 1000}',
        'style': '--car-dur:${duration}ms',
        'aria-roledescription': 'carrusel',
        'aria-label': 'Destacados',
      },
      [
        for (var index = 0; index < slides.length; index++)
          _slide(slides[index], index, slides.length),
        if (many && (showArrows || showIndicators))
          div(classes: 'car-nav', [
            if (showArrows)
              button(
                classes: 'car-arrow prev',
                attributes: {
                  'type': 'button',
                  'aria-label': 'Diapositiva anterior',
                  'data-car-prev': '',
                },
                [RawText(materialIcon(mdChevronLeft, size: 28))],
              ),
            if (showIndicators)
              div(classes: 'car-dots', [
                for (var index = 0; index < slides.length; index++)
                  button(
                    classes: 'car-dot',
                    attributes: {
                      'type': 'button',
                      'aria-label':
                          'Diapositiva ${index + 1} de ${slides.length}',
                      'aria-pressed': index == 0 ? 'true' : 'false',
                      'data-car-go': '$index',
                    },
                    [span(const [])],
                  ),
              ]),
            if (showArrows)
              button(
                classes: 'car-arrow next',
                attributes: {
                  'type': 'button',
                  'aria-label': 'Diapositiva siguiente',
                  'data-car-next': '',
                },
                [RawText(materialIcon(mdChevronRightSharp, size: 28))],
              ),
          ]),
      ],
    );
  }

  Component _slide(Map<String, dynamic> slide, int index, int count) {
    final first = index == 0;
    final title = (slide['title'] ?? '').toString().trim();
    final subtitle = (slide['subtitle'] ?? '').toString().trim();
    final action = resolveWebsiteCarouselSlideAction(slide);
    final href = action == null ? null : context.publicHref(action.href);
    final image = (slide['imageUrl'] ?? '').toString().trim();
    final alt = (slide['imageAltText'] ?? slide['altText'] ?? '').toString();
    final showOverlay = (slide['showOverlay'] ?? true) == true;
    final opacity = (numberValue(slide['overlayOpacity']) ?? 0.55).clamp(
      0.0,
      1.0,
    );
    final authored = _authoredBackground(slide);
    final fx = (numberValue(slide['focalPointX']) ?? 0.5).clamp(0.0, 1.0);
    final fy = (numberValue(slide['focalPointY']) ?? 0.5).clamp(0.0, 1.0);
    final overlay = showOverlay
        ? 'background:linear-gradient('
              '${const WebsiteRgba(1, 0, 0, 0).withAlpha(opacity * 0.4).css},'
              '${const WebsiteRgba(1, 0, 0, 0).withAlpha(opacity * 0.7).css})'
        : null;
    final background = authored ?? '#1a1a1a';
    return div(
      classes: first ? 'car-slide on' : 'car-slide',
      attributes: {
        'data-slide': '$index',
        'role': 'group',
        'aria-roledescription': 'diapositiva',
        'aria-label': '${index + 1} de $count',
        if (!first) 'inert': '',
        'style': image.isEmpty && authored == null
            // No photo and no color of its own: the old dark gradient.
            ? 'background:linear-gradient(to bottom right,#1a1a1a,'
                  '${WebsiteRgba.lerp(WebsiteRgba.fromArgb(0xFF1A1A1A), const WebsiteRgba(1, 0, 0, 0), 0.2).css})'
            : 'background:$background',
      },
      [
        if (image.isNotEmpty)
          // A later slide's photo waits for its turn (`data-src`, set by the
          // script before the slide shows): stacked under the first one, a
          // lazy photo is still «in view» and was fetched with it, and a
          // 2 MB third slide took the phone's bandwidth from an 82 KB first
          // photo (5 s to see it on a slow phone, 2026-10-05).
          Component.element(
            tag: 'img',
            classes: 'car-img',
            attributes: {
              if (first) 'src': image else 'data-src': image,
              'alt': alt,
              'style':
                  'object-position:${cssNum(fx * 100)}% ${cssNum(fy * 100)}%',
              if (first) 'fetchpriority': 'high',
              'decoding': first ? 'sync' : 'async',
            },
          ),
        if (carouselSlideUsesComposition(slide)) ...[
          if (overlay != null)
            div(classes: 'car-ov', attributes: {'style': overlay}, const []),
          CanvasLayersView(_slideDocument(slide), context, deferImages: !first),
        ] else
          div(
            classes: 'car-in',
            attributes: {'style': ?overlay},
            [
              div(classes: 'car-col', [
                if (title.isNotEmpty)
                  Component.element(
                    // The home's first words are its heading.
                    tag: first ? 'h1' : 'h2',
                    classes: 'car-t',
                    attributes: {
                      'style': _textStyle(
                        slide['titleFormatting'],
                        size: context.theme.headingSize,
                        height: 1.12,
                      ),
                    },
                    children: [.text(title.toUpperCase())],
                  ),
                if (subtitle.isNotEmpty)
                  p(
                    classes: 'car-s',
                    attributes: {
                      'style': _textStyle(
                        slide['subtitleFormatting'],
                        size: context.theme.bodySize * 1.2,
                        height: 32 / 24,
                      ),
                    },
                    [.text(subtitle)],
                  ),
                if (action != null && href != null)
                  a(
                    classes: 'w-btn on-dark ${action.variant.storageValue}',
                    href: href,
                    [.text(action.label.toUpperCase())],
                  ),
              ]),
            ],
          ),
      ],
    );
  }

  /// The slide's own solid color (`WebsiteBlockSurfaceStyle` with
  /// `backgroundType: solid`), if it has one.
  static String? _authoredBackground(Map<String, dynamic> slide) {
    final style = slide['style'];
    if (style is! Map || style['backgroundType'] != 'solid') return null;
    final color = hexColor(
      style['backgroundColor'],
      const WebsiteRgba(0, 0, 0, 0),
    );
    return color.a == 0 ? null : color.css;
  }

  /// The size, line and look a slide's formatting sets on its text
  /// (`TextFormatting.applyTo`) over the slide's own [size] and [height].
  static String _textStyle(
    Object? raw, {
    required double size,
    required double height,
  }) {
    final formatting = raw is Map ? raw : const {};
    final fontSize = numberValue(formatting['fontSize']) ?? size;
    final lineHeight = numberValue(formatting['lineHeight']) ?? height;
    final spacing = numberValue(formatting['letterSpacing']);
    final color = formatting['textColor'];
    final align = switch (formatting['textAlign']) {
      'right' || 'end' => 'right',
      _ => null,
    };
    final rules = [
      'font-size:${cssPx(fontSize)}',
      'line-height:${lineHeightPx(fontSize, lineHeight)}',
      if (spacing != null) 'letter-spacing:${cssPx(spacing)}',
      if (color is int) 'color:${WebsiteRgba.fromArgb(color).css}',
      if (formatting['italic'] == true) 'font-style:italic',
      if (formatting['underline'] == true) 'text-decoration:underline',
      if (align != null) 'text-align:$align',
    ];
    return rules.join(';');
  }
}

/// Plays every carousel on the page as `_WebsiteCarouselBlockContentState`:
/// the next slide every interval (none when the visitor asks for less
/// motion), arrows, dots and a swipe. A slide is shown once its images are
/// ready, and the one after it is fetched while it shows; the second one
/// only once the page has loaded, so it never competes with the first.
const carouselScript = r'''
document.querySelectorAll("[data-car]").forEach(function(c){
var slides=[].slice.call(c.querySelectorAll(":scope>.car-slide")),dots=[].slice.call(c.querySelectorAll(".car-dot"));
var n=slides.length,cur=0,want=-1,timer=0,ms=+c.dataset.interval||0;
var still=matchMedia("(prefers-reduced-motion: reduce)").matches;
function ready(i){return Promise.all([].map.call(slides[i].querySelectorAll("img"),function(m){if(m.dataset.src){m.src=m.dataset.src;m.removeAttribute("data-src")}m.loading="eager";return m.decode?m.decode().catch(function(){}):0}))}
function restart(){clearInterval(timer);if(ms&&!still&&n>1)timer=setInterval(function(){go(cur+1)},ms)}
function show(i){var old=slides[cur];old.classList.remove("on");old.inert=true;slides[i].classList.add("on");slides[i].inert=false;dots.forEach(function(d,k){d.setAttribute("aria-pressed",k===i?"true":"false")});cur=i;ready((i+1)%n);restart()}
function go(i){i=(i%n+n)%n;if(i===cur){want=-1;restart();return}clearInterval(timer);want=i;ready(i).then(function(){if(want===i){want=-1;show(i)}})}
c.addEventListener("click",function(e){var b=e.target.closest("button");if(!b||!c.contains(b))return;if(b.hasAttribute("data-car-prev"))go(cur-1);else if(b.hasAttribute("data-car-next"))go(cur+1);else if(b.dataset.carGo)go(+b.dataset.carGo)});
var x0=null,y0=0,t0=0;
c.addEventListener("touchstart",function(e){if(e.touches.length!==1){x0=null;return}x0=e.touches[0].clientX;y0=e.touches[0].clientY;t0=Date.now()},{passive:true});
c.addEventListener("touchend",function(e){if(x0===null||n<2)return;var t=e.changedTouches[0],dx=t.clientX-x0,dy=t.clientY-y0,dt=Math.max(1,Date.now()-t0);x0=null;if(Math.abs(dx)<18||Math.abs(dx)<Math.abs(dy))return;if(Math.abs(dx)>=c.clientWidth/4||Math.abs(dx)/dt*1000>=50)go(dx<0?cur+1:cur-1)},{passive:true});
function warm(){if(n>1)ready(1)}
if(document.readyState==="complete")warm();else addEventListener("load",warm);
restart();
});
''';
