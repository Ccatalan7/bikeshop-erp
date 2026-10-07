import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
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
  for (final (_, slide) in _storedSlides(data)) slide,
];

/// The slides with their places in the stored list, which is how the editor
/// addresses one ([BlockRenderContext.editText]); an entry that is not a
/// slide is skipped.
List<(int, Map<String, dynamic>)> _storedSlides(Map<String, dynamic> data) => [
  if (data['slides'] case final List<Object?> slides)
    for (final (index, slide) in slides.indexed)
      if (slide is Map) (index, Map<String, dynamic>.from(slide)),
];

/// A slide drawn as layers (`websiteCarouselSlideUsesComposition`).
bool carouselSlideUsesComposition(Map<String, dynamic> slide) =>
    slide['useComposition'] == true ||
    (slide['elements'] is List && (slide['elements'] as List).isNotEmpty);

/// The video a slide plays behind its content, as `_buildSlide` picks it:
/// its uploaded file, else the YouTube video its link names; `null` for a
/// link that names none (Flutter then draws the slide without video).
({String? file, String? youtube})? carouselSlideVideo(
  Map<String, dynamic> slide,
) {
  final file = (slide['videoFileUrl'] ?? '').toString().trim();
  if (file.isNotEmpty) return (file: file, youtube: null);
  final link = (slide['videoUrl'] ?? '').toString().trim();
  final youtube = link.isEmpty ? null : websiteYouTubeVideoId(link);
  return youtube == null ? null : (file: null, youtube: youtube);
}

/// What the HTML carousel draws: photo, color and video slides, with or
/// without layers it covers.
bool carouselIsCovered(Map<String, dynamic> data) {
  for (final slide in carouselSlides(data)) {
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
    final stored = [for (final (index, _) in _storedSlides(data)) index];
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
        // In the editor's draft it stays on its slide, as on the canvas
        // (`_autoPlay` is off while editing): a text being written does not
        // slide away.
        if (autoPlay && many && !context.draft)
          'data-interval': '${interval * 1000}',
        'style': '--car-dur:${duration}ms',
        'aria-roledescription': 'carrusel',
        'aria-label': 'Destacados',
      },
      [
        for (var index = 0; index < slides.length; index++)
          _slide(slides[index], index, slides.length, stored[index]),
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

  Component _slide(
    Map<String, dynamic> slide,
    int index,
    int count,
    int stored,
  ) {
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
    final video = carouselSlideVideo(slide);
    // A video slide is the dark #1a1a1a with the video over it, whatever
    // color the slide has (`_buildSlide`).
    final background = video != null ? '#1a1a1a' : authored ?? '#1a1a1a';
    return div(
      classes: [
        'car-slide',
        if (first) 'on',
        // No color of its own: under a block's own background it lets
        // that one through (`letsBlockBackgroundThrough`).
        if (authored == null && video == null) 'dflt',
      ].join(' '),
      attributes: {
        'data-slide': '$index',
        'role': 'group',
        'aria-roledescription': 'diapositiva',
        'aria-label': '${index + 1} de $count',
        if (!first) 'inert': '',
        'style': image.isEmpty && authored == null && video == null
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
        if (video != null) _media(video, image: image, title: title),
        if (carouselSlideUsesComposition(slide)) ...[
          if (overlay != null)
            div(classes: 'car-ov', attributes: {'style': overlay}, const []),
          CanvasLayersView(
            _slideDocument(slide),
            context,
            deferImages: !first,
            slide: stored,
          ),
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
                      ...context.editText(
                        const ['title'],
                        collection: const ['slides'],
                        index: stored,
                      ),
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
                      ...context.editText(
                        const ['subtitle'],
                        collection: const ['slides'],
                        index: stored,
                      ),
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
                    attributes: context.editButton(
                      WebsiteButtonFields.slide,
                      index: stored,
                    ),
                    [.text(action.label.toUpperCase())],
                  ),
              ]),
            ],
          ),
      ],
    );
  }

  /// The slide's video, muted and looping behind its content and inert to
  /// the pointer. Its source waits in `data-vsrc` until the slide shows and
  /// the page has loaded (the script plays only the slide on screen, and
  /// none for a visitor who asks for less motion); the photo stays under it
  /// and is the file's poster, so the slide is never an empty dark box.
  Component _media(
    ({String? file, String? youtube}) video, {
    required String image,
    required String title,
  }) {
    final youtube = video.youtube;
    return div(
      classes: 'car-media',
      attributes: {'aria-hidden': 'true'},
      [
        if (youtube != null)
          Component.element(
            tag: 'iframe',
            attributes: {
              'data-vsrc':
                  'https://www.youtube.com/embed/$youtube?autoplay=1&mute=1'
                  '&loop=1&playlist=$youtube&controls=0&rel=0'
                  '&modestbranding=1&playsinline=1&enablejsapi=1'
                  '&origin=${Uri.encodeQueryComponent(context.storeUrl)}',
              'title': title.isEmpty ? 'Video' : title,
              'allow': 'autoplay; encrypted-media',
              'tabindex': '-1',
            },
          )
        else
          Component.element(
            tag: 'video',
            attributes: {
              'data-vsrc': video.file!,
              'muted': '',
              'loop': '',
              'playsinline': '',
              'preload': 'none',
              if (image.isNotEmpty) 'poster': image,
            },
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
/// motion), arrows, dots and a swipe. Only the slide on screen plays its
/// video, from the page's load on, and none plays for less motion. A
/// YouTube player is told to pause only once it said it is ready (the
/// `listening` handshake of its iframe API); hidden before then, it is
/// unloaded, or it would start on its own (`autoplay`) off screen. A slide is shown once its images are
/// ready, and the one after it is fetched while it shows; the second one
/// only once the page has loaded, so it never competes with the first. The
/// editor's draft turns it to a slide (`car:go`) and hears where it is
/// (`car:shown`).
const carouselScript = r'''
document.querySelectorAll("[data-car]").forEach(function(c){
var slides=[].slice.call(c.querySelectorAll(":scope>.car-slide")),dots=[].slice.call(c.querySelectorAll(".car-dot"));
var n=slides.length,cur=0,want=-1,timer=0,ms=+c.dataset.interval||0,loaded=false,frames=[].slice.call(c.querySelectorAll(".car-media iframe"));
var still=matchMedia("(prefers-reduced-motion: reduce)").matches;
function yt(v,f){if(v.contentWindow)v.contentWindow.postMessage('{"event":"command","func":"'+f+'","args":[]}',"*")}
function blank(v){return !v.src||v.src==="about:blank"}
function hear(v){if(v.dataset.hears)return;v.dataset.hears="1";v.addEventListener("load",function(){if(blank(v))return;var k=0,t=setInterval(function(){if(v.dataset.ready||blank(v)||++k>40){clearInterval(t);return}if(v.contentWindow)v.contentWindow.postMessage('{"event":"listening","id":"car","channel":"widget"}',"*")},250)})}
function media(i,on){[].forEach.call(slides[i].querySelectorAll(".car-media video,.car-media iframe"),function(v){var frame=!v.play;if(on){if(still||!loaded)return;if(v.dataset.vsrc){if(frame)hear(v);v.src=v.dataset.vsrc;v.removeAttribute("data-vsrc");if(!frame)v.play().catch(function(){})}else if(frame)yt(v,"playVideo");else v.play().catch(function(){})}else if(!v.dataset.vsrc){if(!frame)v.pause();else if(v.dataset.ready)yt(v,"pauseVideo");else{v.dataset.vsrc=v.src;v.src="about:blank"}}})}
addEventListener("message",function(e){if(!/^https:\/\/www\.youtube(-nocookie)?\.com$/.test(e.origin))return;var v=frames.filter(function(f){return f.contentWindow===e.source})[0],d;if(!v||v.dataset.ready)return;try{d=JSON.parse(e.data)}catch(_){return}if(!d||!/^(onReady|initialDelivery|infoDelivery)$/.test(d.event))return;v.dataset.ready="1";if(slides.indexOf(v.closest(".car-slide"))!==cur)yt(v,"pauseVideo")});
function ready(i){return Promise.all([].map.call(slides[i].querySelectorAll("img"),function(m){if(m.dataset.src){m.src=m.dataset.src;m.removeAttribute("data-src")}m.loading="eager";return m.decode?m.decode().catch(function(){}):0}))}
function restart(){clearInterval(timer);if(ms&&!still&&n>1)timer=setInterval(function(){go(cur+1)},ms)}
function show(i){var old=slides[cur];media(cur,false);media(i,true);old.classList.remove("on");old.inert=true;slides[i].classList.add("on");slides[i].inert=false;dots.forEach(function(d,k){d.setAttribute("aria-pressed",k===i?"true":"false")});cur=i;ready((i+1)%n);restart();c.dispatchEvent(new CustomEvent("car:shown",{detail:i,bubbles:true}))}
function go(i){i=(i%n+n)%n;if(i===cur){want=-1;restart();return}clearInterval(timer);want=i;ready(i).then(function(){if(want===i){want=-1;show(i)}})}
c.addEventListener("car:go",function(e){var i=+e.detail;if(isFinite(i))go(Math.floor(i))});
c.addEventListener("click",function(e){var b=e.target.closest("button");if(!b||!c.contains(b))return;if(b.hasAttribute("data-car-prev"))go(cur-1);else if(b.hasAttribute("data-car-next"))go(cur+1);else if(b.dataset.carGo)go(+b.dataset.carGo)});
var x0=null,y0=0,t0=0;
c.addEventListener("touchstart",function(e){if(e.touches.length!==1){x0=null;return}x0=e.touches[0].clientX;y0=e.touches[0].clientY;t0=Date.now()},{passive:true});
c.addEventListener("touchend",function(e){if(x0===null||n<2)return;var t=e.changedTouches[0],dx=t.clientX-x0,dy=t.clientY-y0,dt=Math.max(1,Date.now()-t0);x0=null;if(Math.abs(dx)<18||Math.abs(dx)<Math.abs(dy))return;if(Math.abs(dx)>=c.clientWidth/4||Math.abs(dx)/dt*1000>=50)go(dx<0?cur+1:cur-1)},{passive:true});
function warm(){loaded=true;media(cur,true);if(n>1)ready(1)}
if(document.readyState==="complete")warm();else addEventListener("load",warm);
restart();
});
''';
