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
/// Google rating, the plan category's items as cards, every other item by
/// its category with its price (a search filters them as the visitor types,
/// and without script by the URL), and the closing band.
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

Component _hero(CatalogPageModel page) {
  final look = page.presentation;
  final rating = look.heroShowRating
      ? CatalogPriceListRating.read(page.shell.setting)
      : null;
  return section(
    classes: [
      'pl-hero',
      if (page.heroImage.isNotEmpty) 'photo',
      if (look.heroAlignment == WebsiteCatalogHeroAlignment.center) 'center',
    ].join(' '),
    attributes: {
      if (page.heroImage.isNotEmpty)
        'style': '--shade:${look.heroOverlay.toStringAsFixed(2)}',
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
          if (look.heroAction case final action?)
            if (_action(page, action, 'pl-btn', whatsappIcon: true)
                case final button?)
              div(classes: 'pl-actions', [button]),
        ]),
        if (rating != null)
          aside(
            classes: 'pl-rating',
            attributes: {
              'aria-label': 'Calificación en Google: ${rating.label} de 5',
            },
            [
              div(classes: 'pl-rating-row', [
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
              ]),
              if (rating.totalLabel.isNotEmpty) p([.text(rating.totalLabel)]),
            ],
          ),
      ]),
    ],
  );
}

Component _plans(CatalogPageModel page) {
  final shell = page.shell;
  final list = page.priceList!;
  final id = page.presentation.plansCategoryId;
  final title = shell.categoryName(id);
  final intro = (shell.categories[id]?['description'] ?? '').toString().trim();
  final fullest = list.fullestPlan;
  return section(classes: 'pl-plans', [
    div(classes: 'pl-in', [
      div(classes: 'pl-head', [
        h2([.text(title.isEmpty ? 'Planes' : title)]),
        if (intro.isNotEmpty) p([.text(intro)]),
      ]),
      div(classes: 'pl-plan-row', [
        for (final plan in list.plans)
          article(
            classes: identical(plan, fullest) ? 'pl-plan hi' : 'pl-plan',
            [
              div(classes: 'pl-plan-top', [
                h3([
                  a(href: page.pathById[plan.item.id] ?? page.rootPath, [
                    .text(plan.item.name),
                  ]),
                ]),
                if (identical(plan, fullest))
                  span(classes: 'pl-pill', [.text('La más completa')]),
              ]),
              p(classes: 'pl-plan-price', [.text(plan.item.priceLabel)]),
              if (plan.includes.isNotEmpty)
                ul(classes: 'pl-inc', [
                  for (final include in plan.includes)
                    li([
                      RawText(_check),
                      span([
                        .text(include.title),
                        if (include.detail.isNotEmpty)
                          span(classes: 'pl-inc-d', [.text(include.detail)]),
                      ]),
                    ]),
                ]),
              if (page.presentation.heroAction case final action?)
                ?_action(page, action, 'pl-btn pl-plan-btn'),
            ],
          ),
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
  String count(int value) =>
      '$value ${value == 1 ? page.singularNoun : page.noun}';
  return section(classes: 'pl-list', [
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
                  [.text(count(shown[group.categoryId]!))],
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
  ]);
}

Component _closing(CatalogPageModel page) {
  final look = page.presentation;
  return section(classes: 'pl-closing', [
    div(classes: 'pl-in pl-closing-in', [
      div([
        if (look.closingTitle.isNotEmpty) h2([.text(look.closingTitle)]),
        if (look.closingText.isNotEmpty) p([.text(look.closingText)]),
      ]),
      if (look.closingAction case final action?)
        ?_action(page, action, 'pl-btn', whatsappIcon: true),
    ]),
  ]);
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
.pl-hero-in{position:relative;z-index:2;display:flex;flex-wrap:wrap;justify-content:space-between;align-items:flex-end;gap:40px;padding-block:64px 72px}
.pl-hero.center .pl-hero-in{justify-content:center;text-align:center}
.pl-hero-text{flex:1 1 560px;max-width:720px}
.pl-crumbs{margin:0 0 20px;font:400 14px/20px var(--body);color:rgb(255 255 255 / .66)}
.pl-crumbs a{color:inherit;text-decoration:none}.pl-crumbs a:hover{color:#fff}
.pl-eyebrow{margin:0 0 14px;font:600 13px/1 var(--body);letter-spacing:.16em;text-transform:uppercase;color:rgb(255 255 255 / .78)}
.pl-hero h1{margin:0;font:500 clamp(46px,6vw,76px)/.98 var(--head);text-transform:uppercase;text-wrap:balance}
.pl-intro{margin:22px 0 0;max-width:560px;font:400 19px/1.5 var(--body);color:rgb(255 255 255 / .82)}
.pl-actions{display:flex;flex-wrap:wrap;gap:14px;margin-top:32px}
.pl-hero.center .pl-actions,.pl-hero.center .pl-intro{justify-content:center;margin-inline:auto}
.pl-btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;min-height:52px;padding:0 26px;border:1.5px solid transparent;border-radius:6px;font:700 15px/1.2 var(--body);letter-spacing:.06em;text-transform:uppercase;text-decoration:none;text-align:center;transition:background-color .2s,border-color .2s,color .2s}
.pl-btn.filled{background:var(--pl-acc);border-color:var(--pl-acc);color:var(--pl-onacc)}
.pl-btn.filled:hover{background:color-mix(in srgb,var(--pl-acc) 88%,#000)}
.pl-btn.outline{border-color:rgb(255 255 255 / .75);color:#fff}
.pl-btn.outline:hover,.pl-btn.text:hover{background:rgb(255 255 255 / .1)}
.pl-btn.text{color:#fff;text-decoration:underline;text-underline-offset:4px}
.pl-btn:focus-visible{outline:2px solid #fff;outline-offset:2px}
.pl-rating{flex:0 1 300px;padding:24px 26px;border:1px solid rgb(255 255 255 / .22);border-radius:8px}
.pl-rating-row{display:flex;align-items:baseline;gap:12px}
.pl-rating-n{font:500 58px/1 var(--head);font-variant-numeric:tabular-nums}
.pl-stars{position:relative;display:inline-block;font-size:22px;line-height:1;letter-spacing:2px;color:rgb(255 255 255 / .28)}
.pl-stars::before{content:"★★★★★"}
.pl-stars span{position:absolute;left:0;top:0;width:var(--fill);overflow:hidden;white-space:nowrap;color:var(--pl-acc)}
.pl-rating p{margin:8px 0 0;font:400 15px/1.4 var(--body);color:rgb(255 255 255 / .74)}

.pl-head{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:flex-end;gap:16px 32px}
.pl-head h2{margin:0;font:500 clamp(32px,4vw,44px)/1.05 var(--head);text-transform:uppercase;color:var(--pl-ink)}
.pl-head p{margin:0;max-width:420px;font:400 16px/1.5 var(--body);color:var(--pl-mute)}
.pl-head.line{padding-bottom:26px;border-bottom:2px solid var(--pl-ink)}

.pl-plans{padding-block:80px;background:var(--pl-paper)}
.pl-plan-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr));margin-top:34px;border:1px solid var(--pl-line);border-radius:8px;overflow:hidden;background:var(--pl-bg)}
.pl-plan{display:flex;flex-direction:column;padding:32px 30px;border-right:1px solid var(--pl-line);border-bottom:1px solid var(--pl-line);margin:0 -1px -1px 0;color:var(--pl-ink)}
.pl-plan.hi{background:var(--pl-navy);color:#fff}
.pl-plan-top{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
.pl-plan h3{margin:0;font:500 24px/1.15 var(--head);text-transform:uppercase}
.pl-plan h3 a{color:inherit;text-decoration:none}.pl-plan h3 a:hover{text-decoration:underline;text-underline-offset:4px}
.pl-pill{flex:none;padding:5px 9px;border-radius:4px;background:var(--pl-acc);font:700 11px/1.2 var(--body);letter-spacing:.1em;text-transform:uppercase;color:var(--pl-onacc)}
.pl-plan-price{margin:18px 0 0;font:500 44px/1 var(--head);font-variant-numeric:tabular-nums}
.pl-inc{display:flex;flex-direction:column;gap:11px;margin:22px 0 0;padding:20px 0 0;border-top:1px solid var(--pl-line);list-style:none}
.pl-plan.hi .pl-inc{border-top-color:rgb(255 255 255 / .2)}
.pl-inc li{display:flex;gap:10px;font:400 15px/1.45 var(--body)}
.pl-ck{flex:none;margin-top:2px;color:var(--pl-prim)}
.pl-plan.hi .pl-ck{color:var(--pl-acc)}
.pl-inc-d{display:block;margin-top:2px;font-size:14px;color:var(--pl-mute)}
.pl-plan.hi .pl-inc-d{color:rgb(255 255 255 / .7)}
.pl-plan-btn{margin-top:auto;padding-top:0;align-self:stretch}
.pl-inc+.pl-plan-btn,.pl-plan-price+.pl-plan-btn{margin-top:28px}
.pl-plan:not(.hi) .pl-btn.outline{border-color:var(--pl-ink);color:var(--pl-ink)}
.pl-plan:not(.hi) .pl-btn.text{color:var(--pl-ink)}
.pl-plan:not(.hi) .pl-btn.outline:hover,.pl-plan:not(.hi) .pl-btn.text:hover{background:color-mix(in srgb,var(--pl-ink) 6%,transparent)}

.pl-list{padding-block:84px 96px;background:var(--pl-bg)}
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

@media (max-width:899px){
.pl-group{grid-template-columns:minmax(0,1fr);gap:14px}
}
@media (max-width:599px){
.pl-in{padding-inline:20px}
.pl-hero-in{padding-block:40px 44px;gap:24px}
.pl-intro{font-size:17px}
.pl-actions .pl-btn,.pl-closing .pl-btn{flex:1 1 100%}
.pl-rating{flex:1 1 100%;padding:18px 20px}
.pl-rating-n{font-size:40px}
.pl-plans{padding-block:48px}
.pl-plan-row{border:0;border-radius:0;background:transparent;gap:12px;overflow:visible}
.pl-plan{margin:0;border:1px solid var(--pl-line);border-radius:8px;background:var(--pl-bg);padding:24px 20px}
.pl-plan-top{flex-direction:column-reverse;align-items:flex-start;gap:10px}
.pl-plan.hi{border-color:var(--pl-navy);background:var(--pl-navy)}
.pl-plan-price{font-size:34px}
.pl-list{padding-block:48px 56px}
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
