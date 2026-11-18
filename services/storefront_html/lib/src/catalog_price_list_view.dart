import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'catalog_page_model.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart' show BlockRenderContext;

/// A catalog root laid out as a price list ([WebsiteCatalogLayout.priceList],
/// `CatalogPriceListView` in Flutter): the hero with its button and the
/// Google rating, the plan category's items side by side ([_plans]), every
/// other item by its category with its price (a search filters them as the
/// visitor types, and without script by the URL), and the closing band.
Component catalogPriceListDocument(CatalogPageModel page) {
  final shell = page.shell;
  final theme = WebsiteThemeRoles.resolve(shell.setting);
  final meta = page.meta;
  return sitePage(
    context: page.page,
    meta: PageMeta(
      title: meta.title,
      description: meta.description,
      canonicalUrl: meta.canonicalUrl,
      indexable: meta.indexable,
      imageUrl: meta.imageUrl,
      structuredData: meta.structuredData,
      preloadHeadingFont: true,
      styles: catalogPriceListCss(theme),
    ),
    content: [
      _hero(page),
      if (page.priceList!.plans.isNotEmpty) _plans(page),
      _list(page),
      if (page.presentation.hasClosing) _closing(page),
      script(content: _filterScript),
    ],
  );
}

const _check =
    '<svg class="pl-ck" viewBox="0 0 24 24" width="18" height="18" fill="none" '
    'stroke="currentColor" stroke-width="2.2" stroke-linecap="round" '
    'stroke-linejoin="round" aria-hidden="true"><path d="M4.5 12.5l4.5 4.5 '
    '10.5-11"/></svg>';
const _cross =
    '<svg class="pl-x" viewBox="0 0 24 24" width="16" height="16" fill="none" '
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
    'aria-hidden="true"><path d="M7 7l10 10M17 7 7 17"/></svg>';
const _chat =
    '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" '
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
    'stroke-linejoin="round" aria-hidden="true"><path d="M4 20l1.3-3.9A8 8 0 '
    '1 1 8 18.8z"/></svg>';
const _search =
    '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" '
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
    'aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path '
    'd="M20 20l-4.2-4.2"/></svg>';
const _chevron =
    '<svg class="pl-chev" viewBox="0 0 24 24" width="20" height="20" '
    'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
    'stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';

/// An action as the link Flutter follows (`BlockRenderContext.publicHref`:
/// a category by its clean path, `/tienda/…` as public, an anchor kept in the
/// page, an e-mail or a phone as is); `null` hides it, as Flutter hides a
/// destination a visitor may not follow.
Component? _action(
  CatalogPageModel page,
  WebsiteActionValue action,
  String classes, {
  bool whatsappIcon = false,
}) {
  final href = BlockRenderContext(
    shell: page.shell,
    theme: WebsiteThemeRoles.resolve(page.shell.setting),
    storeUrl: page.page.storeUrl,
  ).publicHref(action.href);
  if (href == null) return null;
  final isWhatsapp = href.contains('wa.me/') || href.contains('whatsapp.com');
  return a(classes: '$classes ${action.variant.storageValue}', href: href, [
    if (whatsappIcon && isWhatsapp) RawText(_chat),
    .text(action.label),
  ]);
}

String _slug(String label) => label
    .toLowerCase()
    .replaceAll(RegExp('[áàä]'), 'a')
    .replaceAll(RegExp('[éèë]'), 'e')
    .replaceAll(RegExp('[íìï]'), 'i')
    .replaceAll(RegExp('[óòö]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// The hero as one compact band (owner, 2026-11-18: «I don't know why the
/// fuck that header is so big… make it way more compact»): the trail, the
/// title and the intro on the left; the Google rating as one line and the
/// button on the right, so the plans start within the first screen.
Component _hero(CatalogPageModel page) {
  final look = page.presentation;
  final rating = look.heroShowRating
      ? CatalogPriceListRating.read(page.shell.setting)
      : null;
  final action = look.heroAction == null
      ? null
      : _action(page, look.heroAction!, 'pl-btn', whatsappIcon: true);
  return section(
    classes: [
      'pl-hero',
      if (page.heroImage.isNotEmpty) 'photo',
      if (look.heroAlignment == WebsiteCatalogHeroAlignment.center) 'center',
    ].join(' '),
    attributes: {
      if (page.heroImage.isNotEmpty)
        'style': '--shade:${look.heroOverlay.toStringAsFixed(2)}',
      ...page.pickSection(WebsiteCatalogDraftSection.hero),
    },
    [
      if (page.heroImage.isNotEmpty)
        img(
          src: page.heroImage,
          alt: '',
          attributes: {'fetchpriority': 'high', 'decoding': 'async'},
        ),
      div(classes: 'pl-in pl-hero-in', [
        div(classes: 'pl-hero-text', [
          nav(
            classes: 'pl-crumbs',
            attributes: {'aria-label': 'Migas'},
            [
              a(href: '/', [.text('Inicio')]),
              span(attributes: {'aria-hidden': 'true'}, [.text(' / ')]),
              span([.text(page.rootLabel)]),
            ],
          ),
          if (look.heroEyebrow.isNotEmpty)
            p(classes: 'pl-eyebrow', [.text(look.heroEyebrow)]),
          h1([.text(page.displayTitle)]),
          if (page.intro.isNotEmpty)
            p(classes: 'pl-intro', [.text(page.intro)]),
        ]),
        if (rating != null || action != null)
          div(classes: 'pl-hero-side', [
            if (rating != null)
              aside(
                classes: 'pl-rating',
                attributes: {
                  'aria-label': 'Calificación en Google: ${rating.label} de 5',
                },
                [
                  span(classes: 'pl-rating-n', [.text(rating.label)]),
                  span(
                    classes: 'pl-stars',
                    attributes: {
                      'style':
                          '--fill:${(rating.rating / 5 * 100).toStringAsFixed(0)}%',
                      'aria-hidden': 'true',
                    },
                    [
                      span([.text('★★★★★')]),
                    ],
                  ),
                  if (rating.totalLabel.isNotEmpty)
                    span(classes: 'pl-rating-t', [.text(rating.totalLabel)]),
                ],
              ),
            ?action,
          ]),
      ]),
    ],
  );
}

/// The plans side by side ([CatalogPlanTable]): each plan a column whose
/// head, price and button share their lines with the others' (a CSS subgrid),
/// then the presentation's rows, a plan that does not include one saying so,
/// then what each plan includes that no row holds. On a phone each plan is a
/// band with only what it includes.
Component _plans(CatalogPageModel page) {
  final shell = page.shell;
  final list = page.priceList!;
  final id = page.presentation.plansCategoryId;
  final title = shell.categoryName(id);
  final intro = (shell.categories[id]?['description'] ?? '').toString().trim();
  final fullest = list.fullestPlan;
  final table = list.planTable(page.presentation.planRows);
  final count = table.plans.length;
  final lines = table.cellLines;
  return section(
    classes: 'pl-plans',
    attributes: page.pickSection(WebsiteCatalogDraftSection.plans),
    [
      div(classes: 'pl-in', [
        div(classes: 'pl-head', [
          h2([.text(title.isEmpty ? 'Planes' : title)]),
          if (intro.isNotEmpty) p([.text(intro)]),
        ]),
        div(
          classes: 'pl-table',
          attributes: {
            'style':
                '--pl-cols:${count < 4 ? count : 4};'
                // Two by two on a tablet; three stay in one line rather
                // than leave a hole.
                '--pl-cols-md:${count == 3 ? 3 : (count < 2 ? count : 2)};'
                '--pl-span:${lines + 3};--pl-lines:$lines',
          },
          [
            for (final (index, plan) in table.plans.indexed)
              _planColumn(
                page,
                table,
                index,
                highlighted: identical(plan, fullest),
              ),
          ],
        ),
      ]),
    ],
  );
}

Component _planColumn(
  CatalogPageModel page,
  CatalogPlanTable table,
  int index, {
  required bool highlighted,
}) {
  final plan = table.plans[index];
  final head = table.heads[index];
  final action = page.presentation.heroAction;
  return article(classes: highlighted ? 'pl-col hi' : 'pl-col', [
    div(classes: 'pl-top', [
      if (head.kicker.isNotEmpty || highlighted)
        div(classes: 'pl-top-l', [
          if (head.kicker.isNotEmpty)
            span(classes: 'pl-kick', [.text(head.kicker)]),
          if (highlighted) span(classes: 'pl-pill', [.text('La más completa')]),
        ]),
      h3([
        a(
          href: page.pathById[plan.item.id] ?? page.rootPath,
          attributes: {
            if (head.name != plan.item.name) 'aria-label': plan.item.name,
          },
          [.text(head.name)],
        ),
      ]),
      if (head.note.isNotEmpty) p(classes: 'pl-for', [.text(head.note)]),
    ]),
    p(classes: 'pl-plan-price', [.text(plan.item.priceLabel)]),
    // The button's line stays when there is no button, so the rows below
    // keep theirs.
    div(classes: 'pl-cta', [
      if (action != null) ?_action(page, action, 'pl-btn pl-plan-btn'),
    ]),
    if (table.cellLines > 0)
      ul(classes: 'pl-cells', [
        for (final row in table.rows) _planCell(row.cells[index], row.label),
        for (final include in table.extras[index]) _planCell([include], ''),
      ]),
  ]);
}

/// A cell of a plan's column: the lines of its «qué incluye» on that row,
/// or, when it has none, the row's subject after a cross.
Component _planCell(List<CatalogPlanInclude> includes, String label) {
  if (includes.isEmpty) {
    return li(classes: 'pl-cell no', [
      RawText(_cross),
      span([
        span(classes: 'pl-vh', [.text('No incluye: ')]),
        .text(label),
      ]),
    ]);
  }
  return li(classes: 'pl-cell', [
    RawText(_check),
    span([
      for (final include in includes)
        span(classes: 'pl-line', [
          .text(include.title),
          if (include.detail.isNotEmpty)
            span(classes: 'pl-inc-d', [.text(include.detail)]),
        ]),
    ]),
  ]);
}

Component _list(CatalogPageModel page) {
  final list = page.priceList!;
  final query = page.query.searchQuery;
  // Every service is in the page; the search (`?q=` without script) only
  // hides rows, so clearing it brings them back, as in Flutter.
  final shown = {
    for (final group in list.groups)
      group.categoryId: group.items.where((item) => item.matches(query)).length,
  };
  final anyShown = shown.values.any((count) => count > 0);
  return section(
    classes: 'pl-list',
    attributes: page.pickSection(WebsiteCatalogDraftSection.list),
    [
      div(classes: 'pl-in', [
        div(classes: 'pl-head line', [
          h2([.text('Todos los ${page.noun}')]),
          form(
            classes: 'pl-search',
            action: page.rootPath,
            method: FormMethod.get,
            attributes: {'role': 'search'},
            [
              RawText(_search),
              input(
                type: InputType.search,
                name: 'q',
                value: query,
                attributes: {
                  'placeholder': 'Buscar un ${page.singularNoun}',
                  'aria-label': 'Buscar un ${page.singularNoun}',
                  'autocomplete': 'off',
                  'data-pl-search': '',
                },
              ),
            ],
          ),
        ]),
        if (list.groups.length > 1)
          nav(
            classes: 'pl-chips',
            attributes: {'aria-label': 'Grupos'},
            [
              for (final group in list.groups)
                a(
                  href: '#g-${_slug(group.label)}',
                  attributes: {
                    'data-pl-chip': _slug(group.label),
                    if (shown[group.categoryId] == 0) 'hidden': '',
                  },
                  [
                    .text(group.label),
                    span(
                      attributes: {'data-pl-chip-count': ''},
                      [.text('${shown[group.categoryId]}')],
                    ),
                  ],
                ),
            ],
          ),
        if (list.groups.isEmpty)
          p(classes: 'pl-empty', [
            .text('Todavía no hay ${page.noun} publicados.'),
          ])
        else ...[
          for (final group in list.groups)
            details(
              classes: 'pl-group',
              attributes: {
                'id': 'g-${_slug(group.label)}',
                'open': '',
                if (shown[group.categoryId] == 0) 'hidden': '',
              },
              [
                summary([
                  h3([.text(group.label)]),
                  span(
                    classes: 'pl-count',
                    attributes: {
                      'data-pl-count': '',
                      'data-one': page.singularNoun,
                      'data-many': page.noun,
                    },
                    [.text(page.counted(shown[group.categoryId]!))],
                  ),
                  RawText(_chevron),
                ]),
                ul(classes: 'pl-rows', [
                  for (final item in group.items)
                    li(
                      attributes: {
                        'data-pl-name': item.name,
                        if (!item.matches(query)) 'hidden': '',
                      },
                      [
                        a(href: page.pathById[item.id] ?? page.rootPath, [
                          span(classes: 'pl-name', [.text(item.name)]),
                          span(classes: 'pl-price', [.text(item.priceLabel)]),
                        ]),
                      ],
                    ),
                ]),
              ],
            ),
          p(
            classes: 'pl-empty',
            attributes: {if (anyShown) 'hidden': '', 'data-pl-none': ''},
            [.text('No hay ${page.noun} con ese nombre.')],
          ),
        ],
      ]),
    ],
  );
}

Component _closing(CatalogPageModel page) {
  final look = page.presentation;
  return section(
    classes: 'pl-closing',
    attributes: page.pickSection(WebsiteCatalogDraftSection.closing),
    [
      div(classes: 'pl-in pl-closing-in', [
        div([
          if (look.closingTitle.isNotEmpty) h2([.text(look.closingTitle)]),
          if (look.closingText.isNotEmpty) p([.text(look.closingText)]),
        ]),
        if (look.closingAction case final action?)
          ?_action(page, action, 'pl-btn', whatsappIcon: true),
      ]),
    ],
  );
}

/// Filters the rows as the visitor types (accents and case aside), counts
/// what each group and chip still shows, hides the ones left empty, and on a
/// phone folds every group but the first until one is searched or opened.
const _filterScript = r'''
(function(){
var input=document.querySelector('[data-pl-search]');
var groups=[].slice.call(document.querySelectorAll('.pl-group'));
if(window.matchMedia('(max-width:599px)').matches&&!(input&&input.value)){groups.forEach(function(g,i){if(i>0)g.open=false;});}
if(!input)return;
var norm=function(t){return t.normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase().trim();};
var none=document.querySelector('[data-pl-none]');
input.addEventListener('input',function(){
var q=norm(input.value),any=false;
groups.forEach(function(g){
var shown=0;
[].slice.call(g.querySelectorAll('li[data-pl-name]')).forEach(function(li){var hit=!q||norm(li.getAttribute('data-pl-name')).indexOf(q)>=0;li.hidden=!hit;if(hit)shown++;});
g.hidden=shown===0;if(q&&shown)g.open=true;
var count=g.querySelector('[data-pl-count]');if(count)count.textContent=shown+' '+(shown===1?count.getAttribute('data-one'):count.getAttribute('data-many'));
var chip=document.querySelector('[data-pl-chip="'+g.id.slice(2)+'"]');if(chip){chip.hidden=shown===0;var n=chip.querySelector('[data-pl-chip-count]');if(n)n.textContent=shown;}
if(shown)any=true;
});
if(none)none.hidden=any||groups.length===0;
});
})();
''';

/// The price list's own rules: the theme's primary darkened for the bands,
/// its accent for the buttons with their readable text, the heading font in
/// capitals for the titles and prices.
String catalogPriceListCss(WebsiteThemeRoles theme) {
  final navy = WebsiteRgba.lerp(
    theme.primary,
    const WebsiteRgba(1, 0, 0, 0),
    0.25,
  );
  final paper = WebsiteRgba.lerp(theme.background, theme.primary, 0.05);
  final line = WebsiteRgba.lerp(theme.background, theme.onSurface, 0.13);
  return '''
.pl-hero,.pl-plans,.pl-list,.pl-closing{--pl-navy:${navy.css};--pl-paper:${paper.css};--pl-line:${line.css};--pl-bg:${theme.background.css};--pl-ink:${theme.onSurface.css};--pl-mute:${theme.onSurfaceVariant.css};--pl-prim:${theme.primary.css};--pl-acc:${theme.accent.css};--pl-onacc:${theme.onAccent.css}}
.pl-in{max-width:1200px;margin:0 auto;padding-inline:32px}
.pl-hero{position:relative;overflow:hidden;background:var(--pl-navy);color:#fff}
.pl-hero>img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.pl-hero.photo::before{content:"";position:absolute;inset:0;z-index:1;background:rgb(0 0 0 / var(--shade,.42))}
.pl-hero-in{position:relative;z-index:2;display:flex;justify-content:space-between;align-items:flex-end;gap:16px 48px;padding-block:28px 32px}
.pl-hero-text{flex:1 1 auto;min-width:0;max-width:820px}
.pl-crumbs{margin:0 0 8px;font:400 13px/18px var(--body);color:rgb(255 255 255 / .66)}
.pl-crumbs a{color:inherit;text-decoration:none}.pl-crumbs a:hover{color:#fff}
.pl-eyebrow{margin:0 0 8px;font:600 12px/1 var(--body);letter-spacing:.16em;text-transform:uppercase;color:rgb(255 255 255 / .78)}
.pl-hero h1{margin:0;font:500 clamp(32px,3.4vw,46px)/1 var(--head);text-transform:uppercase;text-wrap:balance}
.pl-intro{margin:8px 0 0;max-width:780px;font:400 16px/1.5 var(--body);color:rgb(255 255 255 / .82);text-wrap:pretty}
.pl-hero-side{flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:12px}
.pl-hero .pl-btn{min-height:48px;padding:0 22px}
.pl-hero.center .pl-hero-in{flex-direction:column;align-items:center;text-align:center}
.pl-hero.center .pl-hero-side{align-items:center}
.pl-hero.center .pl-intro{margin-inline:auto}
.pl-btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;min-height:52px;padding:0 26px;border:1.5px solid transparent;border-radius:6px;font:700 15px/1.2 var(--body);letter-spacing:.06em;text-transform:uppercase;text-decoration:none;text-align:center;transition:background-color .2s,border-color .2s,color .2s}
.pl-btn.filled{background:var(--pl-acc);border-color:var(--pl-acc);color:var(--pl-onacc)}
.pl-btn.filled:hover{background:color-mix(in srgb,var(--pl-acc) 88%,#000)}
.pl-btn.outline{border-color:rgb(255 255 255 / .75);color:#fff}
.pl-btn.outline:hover,.pl-btn.text:hover{background:rgb(255 255 255 / .1)}
.pl-btn.text{color:#fff;text-decoration:underline;text-underline-offset:4px}
.pl-btn:focus-visible{outline:2px solid #fff;outline-offset:2px}
.pl-rating{display:flex;flex-wrap:wrap;align-items:center;gap:4px 8px;font:400 14px/1.3 var(--body);color:rgb(255 255 255 / .74)}
.pl-rating-n{font:500 24px/1 var(--head);color:#fff;font-variant-numeric:tabular-nums}
.pl-stars{position:relative;display:inline-block;font-size:15px;line-height:1;letter-spacing:1px;color:rgb(255 255 255 / .28)}
.pl-stars::before{content:"★★★★★"}
.pl-stars span{position:absolute;left:0;top:0;width:var(--fill);overflow:hidden;white-space:nowrap;color:var(--pl-acc)}

.pl-head{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:flex-end;gap:8px 32px}
.pl-head h2{margin:0;font:500 clamp(26px,2.6vw,34px)/1.05 var(--head);text-transform:uppercase;color:var(--pl-ink)}
.pl-head p{margin:0;max-width:420px;font:400 16px/1.5 var(--body);color:var(--pl-mute)}
.pl-head.line{row-gap:12px;padding-bottom:22px;border-bottom:2px solid var(--pl-ink)}

.pl-plans{padding-block:40px 72px;background:var(--pl-paper)}
.pl-table{display:grid;grid-template-columns:repeat(var(--pl-cols),minmax(0,1fr));column-gap:1px;margin-top:20px;border:1px solid var(--pl-line);background:var(--pl-bg)}
.pl-col{display:grid;grid-row:span var(--pl-span);grid-template-rows:subgrid;row-gap:0;min-width:0;background:var(--pl-bg);color:var(--pl-ink);box-shadow:-1px 0 0 var(--pl-line)}
.pl-col:nth-child(n+5){border-top:1px solid var(--pl-line)}
.pl-col.hi{background:var(--pl-navy);color:#fff}
.pl-top{padding:28px 26px 0}
.pl-top-l{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:8px 12px;min-height:24px;margin-bottom:8px}
.pl-kick{font:600 12px/1.2 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--pl-mute)}
.pl-col.hi .pl-kick{color:rgb(255 255 255 / .72)}
.pl-pill{padding:5px 9px;border-radius:4px;background:var(--pl-acc);font:700 11px/1.2 var(--body);letter-spacing:.1em;text-transform:uppercase;color:var(--pl-onacc)}
.pl-col h3{margin:0;font:500 32px/1.05 var(--head);text-transform:uppercase;text-wrap:balance}
.pl-col h3 a{color:inherit;text-decoration:none}.pl-col h3 a:hover{text-decoration:underline;text-underline-offset:4px}
.pl-for{margin:8px 0 0;font:400 15px/1.4 var(--body);color:var(--pl-mute)}
.pl-col.hi .pl-for{color:rgb(255 255 255 / .74)}
.pl-plan-price{margin:0;padding:20px 26px 0;font:500 44px/1 var(--head);font-variant-numeric:tabular-nums}
.pl-cta{padding:24px 26px 28px}
.pl-plan-btn{width:100%;padding-inline:14px;font-size:14px;letter-spacing:.04em}
.pl-cells{grid-row:span var(--pl-lines);display:grid;grid-template-rows:subgrid;row-gap:0;margin:0;padding:0;list-style:none}
.pl-cell{display:flex;align-items:flex-start;gap:10px;padding:13px 26px;border-top:1px solid var(--pl-line);font:400 15px/1.45 var(--body)}
.pl-col.hi .pl-cell{border-top-color:rgb(255 255 255 / .16)}
.pl-cell.no{color:var(--pl-mute)}
.pl-col.hi .pl-cell.no{color:rgb(255 255 255 / .7)}
.pl-ck{flex:none;margin-top:2px;color:var(--pl-prim)}
.pl-col.hi .pl-ck{color:var(--pl-acc)}
.pl-x{flex:none;margin:3px 1px 0;opacity:.7}
.pl-line{display:block}
.pl-line+.pl-line{margin-top:8px}
.pl-inc-d{display:block;margin-top:2px;font-size:14px;color:var(--pl-mute)}
.pl-col.hi .pl-inc-d{color:rgb(255 255 255 / .7)}
.pl-vh{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
.pl-col:not(.hi) .pl-btn.outline{border-color:var(--pl-ink);color:var(--pl-ink)}
.pl-col:not(.hi) .pl-btn.text{color:var(--pl-ink)}
.pl-col:not(.hi) .pl-btn.outline:hover,.pl-col:not(.hi) .pl-btn.text:hover{background:color-mix(in srgb,var(--pl-ink) 6%,transparent)}

.pl-list{padding-block:64px 88px;background:var(--pl-bg)}
.pl-search{display:flex;align-items:center;gap:10px;width:340px;max-width:100%;min-height:48px;padding:0 14px;border:1px solid var(--pl-line);border-radius:6px;color:var(--pl-mute);background:var(--pl-bg)}
.pl-search:focus-within{border-color:var(--pl-prim);box-shadow:0 0 0 3px color-mix(in srgb,var(--pl-prim) 18%,transparent)}
.pl-search input{flex:1;min-width:0;border:0;outline:none;background:transparent;font:400 16px/1.2 var(--body);color:var(--pl-ink)}
.pl-chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:22px}
.pl-chips a{display:inline-flex;align-items:center;gap:8px;min-height:40px;padding:0 14px;border:1px solid var(--pl-line);border-radius:999px;font:600 14px/1 var(--body);color:var(--pl-ink);text-decoration:none}
.pl-chips a:hover{border-color:var(--pl-ink)}
.pl-chips span{font-weight:500;color:var(--pl-mute);font-variant-numeric:tabular-nums}
.pl-group{display:grid;grid-template-columns:260px minmax(0,1fr);gap:16px 40px;margin-top:48px;scroll-margin-top:96px}
.pl-group>summary{display:block;list-style:none;cursor:default;pointer-events:none}
.pl-group>summary::-webkit-details-marker{display:none}
.pl-group h3{margin:0;font:500 24px/1.15 var(--head);text-transform:uppercase;color:var(--pl-ink)}
.pl-count{display:block;margin-top:8px;font:400 15px/1.3 var(--body);color:var(--pl-mute)}
.pl-chev{display:none}
.pl-rows{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));column-gap:40px;margin:0;padding:0;list-style:none;border-top:1px solid var(--pl-ink);align-content:start}
.pl-rows li{border-bottom:1px solid var(--pl-line)}
.pl-rows a{display:flex;justify-content:space-between;align-items:baseline;gap:16px;min-height:52px;padding:14px 0;color:var(--pl-ink);text-decoration:none}
.pl-rows a:hover .pl-name{text-decoration:underline;text-underline-offset:3px}
.pl-name{font:500 17px/1.35 var(--body)}
.pl-price{flex:none;font:500 20px/1 var(--head);font-variant-numeric:tabular-nums}
.pl-empty{margin:40px 0 0;font:400 17px/1.5 var(--body);color:var(--pl-mute)}

.pl-closing{background:var(--pl-navy);color:#fff}
.pl-closing-in{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:32px;padding-block:88px}
.pl-closing h2{margin:0;font:500 clamp(36px,4.6vw,58px)/1 var(--head);text-transform:uppercase;text-wrap:balance}
.pl-closing p{margin:18px 0 0;max-width:540px;font:400 18px/1.5 var(--body);color:rgb(255 255 255 / .8)}

@media (max-width:1023px){
.pl-table{grid-template-columns:repeat(var(--pl-cols-md),minmax(0,1fr))}
.pl-col:nth-child(n+3){border-top:1px solid var(--pl-line)}
}
@media (max-width:899px){
.pl-hero-in{flex-direction:column;align-items:stretch}
.pl-hero-side{align-items:flex-start}
.pl-group{grid-template-columns:minmax(0,1fr);gap:14px}
}
@media (max-width:599px){
.pl-in{padding-inline:20px}
.pl-hero-in{padding-block:22px 26px}
.pl-intro{font-size:15px}
.pl-hero-side,.pl-hero.center .pl-hero-side{align-items:stretch}
.pl-hero.center .pl-rating{justify-content:center}
.pl-closing .pl-btn{flex:1 1 100%}
.pl-plans{padding-block:28px 40px}
.pl-head p{font-size:15px}
.pl-table{grid-template-columns:minmax(0,1fr);margin-top:18px;margin-inline:-20px;border-inline:0}
.pl-col{display:block;grid-row:auto}
.pl-col+.pl-col{border-top:1px solid var(--pl-line)}
.pl-top{padding:24px 20px 0}
.pl-col h3{font-size:28px}
.pl-plan-price{padding:14px 20px 0;font-size:34px}
.pl-cta{padding:18px 20px 22px}
.pl-cells{display:block}
.pl-cell{padding:12px 20px}
.pl-cell.no{display:none}
.pl-list{padding-block:40px 56px}
.pl-head.line{border-bottom:0;padding-bottom:0}
.pl-search{width:100%}
.pl-chips{display:none}
.pl-group{display:block;margin-top:0;border-bottom:1px solid var(--pl-line)}
.pl-group:first-of-type{margin-top:18px;border-top:2px solid var(--pl-ink)}
.pl-group>summary{display:flex;align-items:center;gap:12px;min-height:60px;cursor:pointer;pointer-events:auto}
.pl-group h3{flex:1;font-size:20px}
.pl-count{margin:0;font-size:14px}
.pl-chev{display:block;color:var(--pl-prim);transition:transform .2s}
.pl-group[open] .pl-chev{transform:rotate(180deg)}
.pl-rows{display:block;border-top:0;padding-bottom:10px}
.pl-rows li{border-bottom:0;border-top:1px solid var(--pl-line)}
.pl-rows a{min-height:48px;padding:12px 0}
.pl-name{font-size:16px}
.pl-price{font-size:18px}
.pl-closing-in{padding-block:56px}
}
''';
}
