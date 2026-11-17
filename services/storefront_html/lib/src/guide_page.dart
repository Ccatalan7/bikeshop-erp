import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/public_store/seo/public_guide.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'css_values.dart';

/// A guide as a row of the index or of «Sigue leyendo».
class GuideCard {
  const GuideCard({
    required this.title,
    required this.path,
    required this.description,
    this.image = '',
  });

  /// A `website_pages` row of a guide.
  factory GuideCard.of(Map<String, dynamic> row) {
    final slug = (row['slug'] ?? '').toString().trim().toLowerCase();
    final title = (row['title'] ?? '').toString().trim();
    return GuideCard(
      title: title.isEmpty ? slug.replaceAll('-', ' ') : title,
      path: websiteGuidePath(slug),
      description: (row['meta_description'] ?? '').toString().trim(),
      image: (row['og_image_url'] ?? '').toString().trim(),
    );
  }

  final String title;
  final String path;
  final String description;

  /// The page's photo, «Foto de la página» in the editor (`og_image_url`):
  /// the same one a shared link to the guide shows. Empty without one.
  final String image;
}

/// The title of the guides' index: its editor page's, else «Guías».
String guidesIndexTitle(Map<String, dynamic>? indexPage) {
  final title = (indexPage?['title'] ?? '').toString().trim();
  return title.isEmpty ? 'Guías' : title;
}

/// What a guide's page draws around its blocks: the trail, its title and
/// summary, when it was published and how long it takes to read, and the
/// other guides after it.
class GuideChrome {
  const GuideChrome({
    required this.indexTitle,
    required this.title,
    required this.lead,
    required this.published,
    required this.updated,
    required this.minutes,
    required this.related,
  });

  final String indexTitle;
  final String title;
  final String lead;
  final DateTime? published;
  final DateTime? updated;
  final int minutes;
  final List<GuideCard> related;

  /// «Publicada el 8 de octubre de 2026 · 6 min de lectura», or
  /// «Actualizada el …» once it changed on a later day.
  String get metaLine {
    final publishedDay = published == null
        ? null
        : websiteGuideDateLabel(published!);
    final updatedDay = updated == null ? null : websiteGuideDateLabel(updated!);
    final date = updatedDay != null && updatedDay != publishedDay
        ? 'Actualizada el $updatedDay'
        : publishedDay == null
        ? null
        : 'Publicada el $publishedDay';
    return [?date, '$minutes min de lectura'].join(' · ');
  }
}

/// The guide's header: trail, title, summary and date, on the guide's
/// column. The trail already names the index, so no label repeats it above
/// the title.
Component guideHeader(GuideChrome guide) => section(
  classes: 'guide-head article',
  [
    div([
      nav(
        classes: 'guide-crumbs',
        attributes: {'aria-label': 'Ruta'},
        [
          a(href: '/', [.text('Inicio')]),
          span(attributes: {'aria-hidden': 'true'}, [.text('/')]),
          a(href: websiteGuidesIndexPath, [.text(guide.indexTitle)]),
          span(attributes: {'aria-hidden': 'true'}, [.text('/')]),
          span(attributes: {'aria-current': 'page'}, [.text(guide.title)]),
        ],
      ),
      h1(classes: 'guide-title', [.text(guide.title)]),
      if (guide.lead.isNotEmpty) p(classes: 'guide-lead', [.text(guide.lead)]),
      p(classes: 'guide-meta', [.text(guide.metaLine)]),
    ]),
  ],
);

/// «Sigue leyendo»: the other guides, newest first, as the index lists them.
Component? guideRelated(GuideChrome guide) {
  if (guide.related.isEmpty) return null;
  return section(classes: 'guide-more', [
    div(classes: 'guide-more-h', [
      h2([.text('Sigue leyendo')]),
    ]),
    guideRows(guide.related),
  ]);
}

/// The guides as ruled rows, each a link: the title over what it answers
/// and, when the guide has a photo, the photo in a grey cell that closes
/// the column on the right and runs from rule to rule.
Component guideRows(List<GuideCard> cards) => ul(classes: 'guide-rows', [
  for (final card in cards)
    li([
      a(
        classes: card.image.isEmpty ? 'guide-row' : 'guide-row has-img',
        href: card.path,
        [
          span(classes: 'guide-row-x', [
            span(classes: 'guide-row-t', [.text(card.title)]),
            if (card.description.isNotEmpty)
              span(classes: 'guide-row-d', [.text(card.description)]),
          ]),
          if (card.image.isNotEmpty)
            span(classes: 'guide-row-f', [
              img(
                src: card.image,
                alt: '',
                loading: MediaLoading.lazy,
                attributes: {'decoding': 'async'},
              ),
            ]),
        ],
      ),
    ]),
]);

/// The index's header: trail, its page's title and description.
Component guidesIndexHeader({required String title, required String lead}) =>
    section(classes: 'guide-head', [
      div([
        nav(
          classes: 'guide-crumbs',
          attributes: {'aria-label': 'Ruta'},
          [
            a(href: '/', [.text('Inicio')]),
            span(attributes: {'aria-hidden': 'true'}, [.text('/')]),
            span(attributes: {'aria-current': 'page'}, [.text(title)]),
          ],
        ),
        h1(classes: 'guide-title', [.text(title)]),
        if (lead.isNotEmpty) p(classes: 'guide-lead', [.text(lead)]),
      ]),
    ]);

/// The index's list, or what it says while there is no guide.
Component guidesIndexList(List<GuideCard> cards) =>
    section(classes: 'guide-list', [
      if (cards.isEmpty)
        p(classes: 'guide-empty', [
          .text('Pronto publicaremos las primeras guías.'),
        ])
      else
        guideRows(cards),
    ]);

/// The rules of the guides: their header, the rows of the index and of
/// «Sigue leyendo», and how a guide draws the editor's blocks
/// (`.guide-body`). Colors and fonts are the theme's (`--primary`,
/// `--head`…), as on every page of the store.
///
/// The owner asked on 2026-11-17 for guides without floating boxes, edge to
/// edge, with boxes, sections and lists aligned to each other. So:
/// - one column for everything a guide draws — the header, the text blocks
///   (800, as the editor sets them), the content of every band, the rows —
///   where the published guides had seven left edges at 1440 px;
/// - a band's grey and every rule reach the window's edges; content never
///   sits in a card: no shadow, no rounded corner, no featured tile;
/// - a guide with a photo shows it in its row, in a grey cell that runs
///   from rule to rule (on the phone, in the row's corner, to the window's
///   edge), never as a tile floating on white;
/// - the cards of a features block are cells that touch, split by rules;
///   its list loses the tinted circles; the stats band is grey, not dark,
///   with figures of a heading's size; titles are the text headings' size
///   and case; the call to action is a ruled band, not a dark panel.
/// A block's own padding (`--sp-*`) still wins over these defaults.
String guidePageCss(WebsiteThemeRoles theme) {
  final heading = cssPx(theme.headingSize);
  return '''
:root{--g-col:800px;--g-pad:var(--w-cp,16px);--g-rule:color-mix(in srgb,var(--ink) 15%,var(--soft))}
.guide-head{background:var(--soft);border-bottom:1px solid var(--line);padding:32px var(--g-pad) 48px}
.guide-head>div{max-width:var(--g-col);margin:0 auto}
.guide-crumbs{display:flex;flex-wrap:wrap;gap:8px;font:400 14px/1.4 var(--body);color:var(--muted)}
.guide-crumbs a{color:var(--muted)}
.guide-crumbs [aria-current]{color:var(--ink)}
.guide-title{margin:28px 0 0;font:600 clamp(36px,5.5vw,64px)/1.04 var(--head);letter-spacing:-.01em;color:var(--ink);text-wrap:balance}
.guide-lead{margin:18px 0 0;font:400 clamp(17px,2.2vw,20px)/1.55 var(--body);color:var(--on-variant)}
.guide-meta{margin:18px 0 0;font:400 14px/1.4 var(--body);color:var(--muted)}
.guide-head+.blocks{padding-top:48px}
.guide-list{padding-bottom:72px}
.guide-list:has(+.blocks){padding-bottom:0}
.guide-list+.blocks>.blk:first-child .ct{border-top:0}
.guide-empty{box-sizing:border-box;max-width:calc(var(--g-col) + 2 * var(--g-pad));margin:0 auto;padding:40px var(--g-pad);font:400 18px/1.5 var(--body);color:var(--muted)}
.guide-rows{margin:0;padding:0;list-style:none}
.guide-rows li{border-bottom:1px solid var(--line);transition:background-color .15s}
.guide-rows li:hover{background:color-mix(in srgb,var(--soft) 50%,var(--w-bg,#fff))}
.guide-row{box-sizing:border-box;display:grid;grid-template-columns:minmax(0,1fr);column-gap:48px;max-width:calc(var(--g-col) + 2 * var(--g-pad));margin:0 auto;padding:0 var(--g-pad);color:var(--ink);text-decoration:none}
.guide-row.has-img{grid-template-columns:minmax(0,1fr) 240px}
.guide-row:focus-visible{outline:2px solid var(--primary);outline-offset:-2px}
.guide-row-x{display:flex;flex-direction:column;justify-content:center;gap:12px;padding:32px 0}
.guide-row-t{font:600 26px/1.18 var(--head);color:var(--ink);text-wrap:balance}
.guide-row:hover .guide-row-t{text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:5px}
.guide-row-d{font:400 16px/1.55 var(--body);color:var(--on-variant)}
.guide-row-f{position:relative;min-height:200px;background:var(--soft)}
.guide-row-f img{position:absolute;inset:0;box-sizing:border-box;width:100%;height:100%;padding:22px;object-fit:contain;mix-blend-mode:multiply}
.guide-more{padding:64px 0 72px;border-top:1px solid var(--line)}
.guide-more-h{box-sizing:border-box;max-width:calc(var(--g-col) + 2 * var(--g-pad));margin:0 auto;padding:0 var(--g-pad) 24px}
.guide-more h2{margin:0;font:600 28px/1.2 var(--head);color:var(--ink)}
.guide-more .guide-rows{border-top:1px solid var(--line)}
@media (max-width:719.98px){
.guide-head{padding:24px var(--g-pad) 36px}
.guide-row-x{padding:24px 0}
.guide-row-t{font-size:22px}
.guide-row.has-img{grid-template-columns:minmax(0,1fr) 104px;column-gap:16px}
.guide-row.has-img .guide-row-x{display:contents}
.guide-row.has-img .guide-row-t{grid-area:1/1;align-self:start;padding-top:22px}
.guide-row.has-img .guide-row-t:last-child{padding-bottom:24px}
.guide-row.has-img .guide-row-d{grid-area:2/1/3/3;padding:14px 0 24px}
.guide-row-f{grid-area:1/2;align-self:start;min-height:0;height:120px;margin-right:calc(-1 * var(--g-pad))}
.guide-row-f img{padding:12px}
.guide-more{padding:48px 0 56px}
}
@media (prefers-reduced-motion:reduce){.guide-rows li{transition:none}}
/* The editor's blocks inside a guide, on the guide's column. A heading
   belongs to the text under it: at most 20 px between them. */
.guide-body .blk:has(>.txt.heading){margin-bottom:min(var(--gap,0px),20px)}
.guide-body :is(.sec-in,.ft-in,.prod-in){max-width:var(--g-col)}
.guide-body :is(.ft-blk,.prod-blk){padding:var(--sp-t,0px) var(--sp-r,0px) var(--sp-b,0px) var(--sp-l,0px)}
.guide-body .sec{padding:var(--sp-t,64px) var(--sp-r,var(--g-pad)) var(--sp-b,64px) var(--sp-l,var(--g-pad))}
.guide-body :is(.sec-t,.st-t,.ct-t){font-size:$heading;line-height:1.15;text-transform:none;max-width:none}
.guide-body :is(.ft-t,.prod-head h2){font-size:$heading;line-height:1.15;text-align:left}
.guide-body .prod-head h2{font-weight:400;letter-spacing:0}
@media (max-width:599.98px){.guide-body :is(.sec-t,.st-t,.ct-t,.ft-t,.prod-head h2){font-size:min($heading,30px);line-height:1.2}}
.guide-body .prod-rows{grid-template-columns:minmax(0,1fr);border-top-color:var(--ink)}
.guide-body .sec-eye{margin:0 0 10px;font:500 16px/1.4 var(--body);letter-spacing:0;text-transform:none;color:var(--s-mut)}
.guide-body .sec-hd.ruled{padding-bottom:24px}
.guide-body .sec[data-tone=dark]{--s-bg:var(--soft);--s-ink:var(--ink);--s-mut:var(--on-variant);--s-soft:var(--on-variant);--s-rule:var(--g-rule);--s-strong:var(--ink);--s-eye:var(--muted);--s-mark:var(--primary);--s-tint:transparent;--s-card:#fff;--s-crule:var(--line);color-scheme:light}
.guide-body .st-grid{margin-top:32px}
.guide-body .st-num{font-size:44px;line-height:44px}
.guide-body .st-suf{font-size:20px;line-height:20px}
.guide-body .st-l{margin-top:12px;font-size:15px}
@container (min-width:600px){.guide-body .st-m{padding:24px 20px 4px}.guide-body .st-m:first-child{padding-left:0}}
@container (max-width:599.98px){.guide-body .st-num{font-size:34px;line-height:36px}.guide-body .st-suf{font-size:16px;line-height:16px}}
.guide-body .fq-cols{display:block}
.guide-body .fq-list{margin-top:28px}
.guide-body .fq-qt{font-size:18px}
.guide-body .fq-a{padding-right:0}
.guide-body .ft-grid{display:grid;grid-auto-flow:column;grid-auto-columns:minmax(0,1fr);align-items:stretch;gap:0;margin-top:28px;border-block:1px solid var(--line)}
.guide-body .ft-card{width:auto;align-items:flex-start;padding:24px 24px 28px;border-left:1px solid var(--line);border-radius:0;background:none;box-shadow:none;text-align:left}
.guide-body .ft-card:first-child{padding-left:0;border-left:0}
.guide-body .ft-card:last-child{padding-right:0}
.guide-body .ft-card .ft-ic{width:28px;height:28px;color:var(--ink)}
.guide-body .ft-ct{margin-top:14px}
.guide-body .ft-list{gap:0;margin-top:28px;border-top:1px solid var(--line)}
.guide-body .ft-row{gap:16px;padding:18px 0;border-bottom:1px solid var(--line)}
.guide-body .ft-dot{width:28px;height:28px;border-radius:0;background:none;color:var(--ink)}
.guide-body .ft-dot svg{width:24px;height:24px}
@container (max-width:599.98px){
.guide-body .ft-grid{grid-auto-flow:row;border-bottom:0}
.guide-body .ft-card,.guide-body .ft-card:first-child,.guide-body .ft-card:last-child{padding:20px 0;border-left:0;border-bottom:1px solid var(--line)}
}
.guide-body .blk:has(>.w-btn.b-blk){align-self:stretch;width:auto}
.guide-body .w-btn.b-blk{margin-left:max(0px,calc((100% - var(--g-col)) / 2));margin-right:auto}
.guide-body .ct-in{display:block;max-width:calc(var(--g-col) + 2 * var(--g-pad));padding:var(--sp-t,56px) var(--sp-r,var(--g-pad)) var(--sp-b,56px) var(--sp-l,var(--g-pad))}
@container (min-width:600px){.guide-body .ct-dl{margin-top:40px;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}}
.guide-body .ct:not(:has(.ct-img)){background:var(--w-bg,#fff);color:var(--ink);border-top:1px solid var(--line)}
.guide-body .ct:not(:has(.ct-img)) .ct-t{color:var(--ink)}
.guide-body .ct:not(:has(.ct-img)) .ct-s{color:var(--on-variant)}
.guide-body .ct:not(:has(.ct-img)) .ct-dl{border-top-color:var(--line)}
.guide-body .ct:not(:has(.ct-img)) .ct-dl dt{color:var(--muted)}
.guide-body .ct:not(:has(.ct-img)) .ct-dl dd{color:var(--ink)}
.guide-body .ct:not(:has(.ct-img)) .ct-line{border-top-color:var(--line);color:var(--on-variant)}
.guide-body .ct:not(:has(.ct-img)) .sec-btn.ghost{border-color:var(--ink);color:var(--ink)}
.guide-body .ct:not(:has(.ct-img)) .sec-btn.ghost:hover{background:var(--ink);color:var(--w-bg,#fff)}
.guide-body .ct:not(:has(.ct-img)) .sec-btn:focus-visible{outline-color:var(--primary)}
''';
}
