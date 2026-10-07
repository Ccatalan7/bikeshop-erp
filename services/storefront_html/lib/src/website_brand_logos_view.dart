import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'block_composition.dart';
import 'website_blocks_view.dart';

/// The brands of a logo block (`brands`, or the older bare `logos`), or
/// Flutter's four placeholders when it has none.
List<Map<String, dynamic>> brandLogoItems(Map<String, dynamic> data) {
  final brands = [
    if (data['brands'] case final List<Object?> items)
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
  ];
  if (brands.isEmpty && data['logos'] is List) {
    for (final url in data['logos'] as List) {
      brands.add({'name': '', 'imageUrl': url.toString()});
    }
  }
  if (brands.isNotEmpty) return brands;
  return [
    for (var index = 1; index <= 4; index++)
      {'name': 'Marca $index', 'imageUrl': ''},
  ];
}

/// `_buildBrandLogos` and `_BrandLogosCarousel`: the title, then the logos
/// sharing the row with 80 px between them, as many to a page as fit at
/// 180 px each, in pages that swipe with a dot per page. The page script
/// makes the pages (`data-brands`); without it the logos share one row.
class BrandLogosView extends StatelessComponent {
  const BrandLogosView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final title = (data['title'] ?? 'MARCAS').toString().trim();
    final height = switch ((data['logoSize'] ?? 'medium').toString()) {
      'small' => 50,
      'large' => 100,
      'xlarge' => 130,
      _ => 80,
    };
    final brands = brandLogoItems(data);
    return section(
      classes: [
        'brands',
        if (composed.block.geometry.exactHeight != null) 'fixed',
      ].join(' '),
      attributes: {'style': '--logo-h:${height}px'},
      [
        div(classes: 'brands-in', [
          h2(
            classes: 'brands-t',
            attributes: {
              ...context.editText(const ['title']),
              ...formattedStyle(
                data['titleFormatting'],
                family: context.theme.headingFont,
                weight: 800,
                fallback: 'var(--head)',
                fontSize: 24,
                lineHeight: 1.5,
              ),
            },
            [.text(title.toUpperCase())],
          ),
          div(
            classes: 'brand-pages',
            attributes: {'data-brands': '${brands.length}'},
            [
              div(classes: 'brand-page', [
                for (final brand in brands) _logo(brand, height),
              ]),
            ],
          ),
          div(classes: 'brand-dots', attributes: {'hidden': ''}, const []),
        ]),
      ],
    );
  }

  Component _logo(Map<String, dynamic> brand, int height) {
    final name = brand['name']?.toString() ?? '';
    final image = brand['imageUrl']?.toString().trim() ?? '';
    final link = brand['link']?.toString().trim() ?? '';
    final href = link.isEmpty ? null : context.publicHref(link);
    final alt = (brand['altText'] ?? brand['name'])?.toString() ?? '';
    final content = image.isNotEmpty
        ? img(
            src: image,
            alt: alt,
            loading: MediaLoading.lazy,
            attributes: {'decoding': 'async'},
          )
        : span(classes: 'brand-ph', [.text(name.isNotEmpty ? name : 'Logo')]);
    if (href != null) {
      return a(classes: 'brand', href: href, [content]);
    }
    return div(classes: 'brand', [content]);
  }
}

/// Pages the logo rows as `_BrandLogosCarousel` does: as many logos to a
/// page as fit at 100 px plus the 80 px gap, every page the whole width (a
/// short last page spreads its logos over it), and a dot per page when there
/// is more than one.
const brandLogosScript = r'''
document.querySelectorAll("[data-brands]").forEach(function(track){
var dots=track.nextElementSibling,items=[].slice.call(track.querySelectorAll(".brand")),n=items.length,k=0;
function layout(){var per=Math.max(1,Math.min(n,Math.floor(track.clientWidth/180)));if(per===k)return;k=per;track.textContent="";dots.textContent="";var pages=Math.ceil(n/k);for(var p=0;p<pages;p++){var page=document.createElement("div");page.className="brand-page";items.slice(p*k,p*k+k).forEach(function(i){page.appendChild(i)});track.appendChild(page);if(pages>1){var d=document.createElement("button");d.type="button";d.className="brand-dot";d.setAttribute("aria-label","Página "+(p+1)+" de "+pages);d.dataset.page=p;dots.appendChild(d)}}dots.hidden=pages<2;mark()}
function mark(){var p=Math.round(track.scrollLeft/Math.max(1,track.clientWidth));[].forEach.call(dots.children,function(d,i){d.setAttribute("aria-current",i===p?"true":"false")})}
dots.addEventListener("click",function(e){var d=e.target.closest(".brand-dot");if(d)track.scrollTo({left:+d.dataset.page*track.clientWidth,behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"auto":"smooth"})});
track.addEventListener("scroll",mark,{passive:true});
layout();addEventListener("resize",layout);
});
''';

/// The block's stylesheet; the logo row's height is `--logo-h`.
const brandLogosCss = '''
/* Its padding (48 and 16) and the row's own 16 at the sides; with an exact
   height, only the 16 at the sides. A side the operator set replaces the
   padding there and drops the row's own (`--sp-*`, BlockSurface). */
.brands{display:flex;flex-direction:column;justify-content:center;background:#fff;padding:var(--sp-t,48px) calc(var(--sp-r,16px) + var(--sp-rx,16px)) var(--sp-b,48px) calc(var(--sp-l,16px) + var(--sp-lx,16px))}
.brands.fixed{height:100%;padding:var(--sp-t,0px) var(--sp-r,16px) var(--sp-b,0px) var(--sp-l,16px)}
.brands-in{display:flex;flex-direction:column;align-items:center;min-width:0}
.brands-t{margin:0;font:400 24px/36px var(--head);letter-spacing:2px;color:rgb(0 0 0 / .87);-webkit-text-stroke:.032em currentColor;text-align:center}
.brand-pages{display:flex;width:100%;height:var(--logo-h);overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;overscroll-behavior-x:contain}
.brand-pages::-webkit-scrollbar{display:none}
.brand-page{flex:0 0 100%;display:flex;gap:80px;scroll-snap-align:start;min-width:0}
.brand{flex:1 1 0;min-width:40px;height:var(--logo-h);display:flex}
.brand img{width:100%;height:100%;object-fit:contain}
.brand-ph{flex:1;display:grid;place-items:center;border:1px solid #e0e0e0;border-radius:8px;background:#f5f5f5;color:#9e9e9e;font:500 12px/1.5 var(--body);text-align:center}
.brand-dots{display:flex;justify-content:center;margin-top:16px}
.brand-dot{width:10px;height:10px;margin:0 4px;padding:0;border:0;border-radius:5px;background:#e0e0e0;cursor:pointer;transition:width .25s}
.brand-dot[aria-current=true]{width:20px;background:var(--w-prim)}
''';
