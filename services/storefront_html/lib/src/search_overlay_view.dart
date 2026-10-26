import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/public_store/models/public_product_question.dart';

import 'material_icons.dart';

/// The header's search (2026-10-24): the magnifier opens a box over the page,
/// which blurs behind it. The box suggests while the visitor types
/// (`/buscar?q=`, [searchOverlayScript]): the categories where the products
/// are, the products with their photo and price, the workshop's services,
/// and «Ver todos» to `/productos?q=`. With nothing typed it shows the
/// visitor's recent searches and the header's own categories. It brings
/// back the Flutter store's search, which the move to HTML had turned into
/// a link to the catalog's search field, and it improves on it: the
/// categories and services, the keyboard, the matched words in bold and
/// a way out when nothing is found. Without JavaScript the
/// magnifier is still the link and the box's form still searches.
///
/// [offersOutOfStock]: the store lets a search include what is out of stock
/// (`PublicProductVisibilityPolicy.offersOutOfStockSearch`), so the box
/// offers «Incluir agotados».
///
/// [api]: where the box asks `/buscar` (the service's own origin, so a
/// suggestion does not go through Firebase Hosting), or empty for the page's.
Component searchOverlay({
  bool offersOutOfStock = false,
  String api = '',
}) => div(
  classes: 'srch',
  attributes: {
    'data-search': '',
    'hidden': '',
    if (api.isNotEmpty) 'data-api': api,
    // «Preguntar por WhatsApp» when nothing is found, with the search.
    'data-ask-missing': PublicProductQuestion.notFoundMessage('{q}'),
  },
  [
    div(classes: 'srch-dim', attributes: {'data-search-close': ''}, const []),
    div(
      classes: 'srch-box',
      attributes: {
        'role': 'dialog',
        'aria-modal': 'true',
        'aria-label': 'Buscar en la tienda',
      },
      [
        form(
          classes: 'srch-bar',
          id: 'srch-form',
          action: '/productos',
          method: FormMethod.get,
          attributes: {'role': 'search'},
          [
            RawText(materialIcon(mdSearch, size: 22, classes: 'srch-icon')),
            input(
              classes: 'srch-input',
              type: InputType.search,
              name: 'q',
              attributes: {
                'placeholder': 'Busca productos, marcas o servicios',
                'autocomplete': 'off',
                'autocapitalize': 'off',
                'spellcheck': 'false',
                'enterkeyhint': 'search',
                'maxlength': '80',
                'role': 'combobox',
                'aria-expanded': 'false',
                'aria-controls': 'srch-list',
                'aria-autocomplete': 'list',
                'aria-label': 'Buscar',
              },
            ),
            button(
              classes: 'srch-clear',
              attributes: {
                'type': 'button',
                'data-search-clear': '',
                'aria-label': 'Borrar la búsqueda',
                'hidden': '',
              },
              [RawText(materialIcon(mdClose, size: 18))],
            ),
            Component.element(
              tag: 'kbd',
              classes: 'srch-esc',
              children: [.text('Esc')],
            ),
            button(
              classes: 'srch-cancel',
              attributes: {'type': 'button', 'data-search-close': ''},
              [.text('Cancelar')],
            ),
            span(
              classes: 'srch-load',
              attributes: {'aria-hidden': 'true'},
              const [],
            ),
          ],
        ),
        // Shown while there is a search; checked, it reads and opens
        // `stock=all`. The browser remembers it for the next search.
        if (offersOutOfStock)
          label(
            classes: 'srch-opt',
            attributes: {'data-search-opt': '', 'hidden': ''},
            [
              input(
                type: InputType.checkbox,
                name: 'stock',
                value: 'all',
                attributes: {'form': 'srch-form', 'data-search-out': ''},
              ),
              span(
                classes: 'srch-switch',
                attributes: {'aria-hidden': 'true'},
                const [],
              ),
              span(classes: 'srch-opt-text', [.text('Incluir agotados')]),
              small([.text('Lo que hoy no tiene stock, con «Agotado»')]),
            ],
          ),
        div(
          classes: 'srch-body',
          id: 'srch-list',
          attributes: {
            'role': 'listbox',
            'aria-label': 'Sugerencias',
            'data-search-body': '',
          },
          const [],
        ),
        p(
          classes: 'srch-live',
          attributes: {'aria-live': 'polite', 'data-search-live': ''},
          const [],
        ),
      ],
    ),
    // The glyphs the script draws, so it carries no icon of its own.
    Component.element(
      tag: 'template',
      attributes: {'data-search-icons': ''},
      children: [
        span(
          attributes: {'data-icon': 'history'},
          [RawText(materialIcon(mdHistoryRounded, size: 18))],
        ),
        span(
          attributes: {'data-icon': 'go'},
          [RawText(materialIcon(mdArrowForwardRounded, size: 18))],
        ),
        span(
          attributes: {'data-icon': 'tool'},
          [RawText(materialIcon(mdBuildOutlined, size: 22))],
        ),
        span(
          attributes: {'data-icon': 'bike'},
          [RawText(materialIcon(mdPedalBikeOutlined, size: 24))],
        ),
      ],
    ),
  ],
);

/// The box's look, on the store's own tokens: the flat grey tile of the
/// product grid for the photos, the heading font and the site's color for
/// the prices, as the cards and the product page show them.
const searchOverlayCss = '''
.srch{position:fixed;inset:0;z-index:60;display:flex;justify-content:center;align-items:flex-start;padding:min(11vh,112px) 16px 16px}
.srch[hidden]{display:none}
.srch-dim{position:absolute;inset:0;background:rgb(15 23 42 / .34);-webkit-backdrop-filter:blur(14px) saturate(1.15);backdrop-filter:blur(14px) saturate(1.15);opacity:0;transition:opacity .24s ease}
.srch.on .srch-dim{opacity:1}
.srch-box{position:relative;display:flex;flex-direction:column;width:min(980px,100%);max-height:min(82vh,780px);background:#fff;border-radius:18px;box-shadow:0 40px 90px -24px rgb(15 23 42 / .55),0 0 0 1px rgb(15 23 42 / .06);overflow:hidden;opacity:0;transform:translateY(-18px) scale(.97);transform-origin:50% 0;transition:opacity .2s ease,transform .34s cubic-bezier(.2,.9,.25,1.12)}
.srch.on .srch-box{opacity:1;transform:none}
.srch-lock,.srch-lock body{overflow:hidden}
.srch-bar{position:relative;flex:none;display:flex;align-items:center;gap:14px;height:72px;margin:0;padding:0 18px 0 22px;border-bottom:1px solid var(--line)}
.srch-icon{flex:none;color:var(--primary)}
.srch-input{flex:1;min-width:0;height:100%;padding:0;border:0;outline:0;background:none;font:500 21px/1.2 var(--body);color:var(--ink);-webkit-appearance:none;appearance:none}
.srch-input:focus,.srch-input:focus-visible{outline:0;box-shadow:none}
.srch-input::placeholder{color:#94a3b8}
.srch-input::-webkit-search-cancel-button{display:none}
.srch-clear{flex:none;display:grid;place-items:center;width:32px;height:32px;padding:0;border:0;border-radius:50%;background:#f1f5f9;color:var(--on-variant);cursor:pointer}
.srch-clear:hover{background:#e2e8f0;color:var(--ink)}
.srch-esc{flex:none;padding:3px 7px;border:1px solid var(--line);border-radius:6px;background:#f8fafc;font:600 11px/1.2 var(--body);color:var(--on-variant)}
.srch-cancel{display:none;flex:none;padding:8px 2px;border:0;background:none;font:600 15px var(--body);color:var(--primary);cursor:pointer}
.srch-load{position:absolute;left:0;right:0;bottom:-1px;height:2px;overflow:hidden;opacity:0;transition:opacity .2s}
.srch-load::after{content:"";position:absolute;top:0;bottom:0;left:0;width:38%;background:var(--primary);transform:translateX(-110%)}
.srch.busy .srch-load{opacity:1}
.srch.busy .srch-load::after{animation:srch-run 1.05s cubic-bezier(.45,0,.2,1) infinite}
@keyframes srch-run{to{transform:translateX(280%)}}
.srch-opt{flex:none;position:relative;display:flex;align-items:center;gap:10px;min-height:44px;padding:6px 24px;border-bottom:1px solid var(--line);font:500 14px/1.3 var(--body);color:var(--ink);cursor:pointer;user-select:none}
.srch-opt[hidden]{display:none}
.srch-opt input{position:absolute;opacity:0;width:1px;height:1px;margin:0}
.srch-switch{flex:none;position:relative;width:34px;height:20px;border-radius:999px;background:#cbd5e1;transition:background-color .18s}
.srch-switch::after{content:"";position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:#fff;box-shadow:0 1px 2px rgb(15 23 42 / .3);transition:transform .18s cubic-bezier(.2,.8,.2,1)}
.srch-opt input:checked+.srch-switch{background:var(--primary)}
.srch-opt input:checked+.srch-switch::after{transform:translateX(14px)}
.srch-opt input:focus-visible+.srch-switch{outline:2px solid var(--primary);outline-offset:2px}
.srch-opt small{font:400 12.5px/1.3 var(--body);color:#64748b}
.srch-none button{display:inline-flex;align-items:center;min-height:44px;margin:16px 8px 0 0;padding:0 20px;border:1px solid var(--ink);border-radius:999px;background:#fff;color:var(--ink);font:600 14px var(--body);cursor:pointer}
.srch-body{flex:1;min-height:0;overflow-y:auto;overscroll-behavior:contain}
.srch-body:empty{display:none}
.srch mark{background:none;color:inherit;font-weight:700}
.srch-sec{padding:14px 0 10px}
.srch-sec+.srch-sec{border-top:1px solid var(--line)}
.srch-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:0;padding:0 24px 8px;font:700 11px/1.4 var(--body);letter-spacing:.12em;text-transform:uppercase;color:#64748b}
.srch-head button{padding:4px 0;border:0;background:none;font:600 12px var(--body);letter-spacing:0;text-transform:none;color:var(--on-variant);cursor:pointer}
.srch-head button:hover{color:var(--ink);text-decoration:underline}
.srch-chips,.srch-cats{display:flex;flex-wrap:wrap;gap:8px;padding:0 24px 4px}
.srch-chip,.srch-cat{display:inline-flex;align-items:center;gap:8px;min-height:36px;padding:0 14px;border:1px solid var(--line);border-radius:999px;background:#fff;font:500 14px/1.2 var(--body);color:var(--ink);text-decoration:none;white-space:nowrap;cursor:pointer;transition:border-color .15s,background-color .15s}
.srch-chip svg{color:#94a3b8}
.srch-cat b{font:600 12px/1 var(--body);color:var(--on-variant);font-variant-numeric:tabular-nums}
.srch-chip:hover,.srch-chip.on,.srch-cat:hover,.srch-cat.on{border-color:var(--ink);background:#f8fafc}
.srch-item{display:grid;grid-template-columns:56px minmax(0,1fr) auto;align-items:center;gap:16px;padding:7px 24px;color:var(--ink);text-decoration:none}
.srch-item:hover,.srch-item.on{background:color-mix(in srgb,var(--ink) 4%,#fff)}
.srch-item.on{box-shadow:inset 3px 0 var(--primary)}
.srch-tile{display:grid;place-items:center;width:56px;height:56px;background:color-mix(in srgb,var(--ink) 6%,#fff);color:#94a3b8;overflow:hidden}
.srch-tile img{width:82%;height:82%;object-fit:contain;mix-blend-mode:multiply}
.srch-tile.tool{justify-self:center;width:40px;height:40px;background:var(--primary);color:#fff}
.srch-tile.tool svg{width:19px;height:19px}
.srch-text{min-width:0;display:flex;flex-direction:column;gap:2px}
.srch-brand{font:700 10.5px/1.3 var(--body);letter-spacing:.12em;text-transform:uppercase;color:#64748b}
.srch-name{font:500 15px/1.35 var(--body);color:var(--ink);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.srch-side{display:flex;flex-direction:column;align-items:flex-end;gap:4px}
.srch-price{font:500 19px/1.1 var(--head);font-variant-numeric:tabular-nums;color:var(--primary);white-space:nowrap}
.srch-out{padding:2px 6px;border:1px solid var(--ink);font:700 10px/1.2 var(--body);letter-spacing:.08em;text-transform:uppercase;color:var(--ink)}
.srch-all{position:sticky;bottom:0;z-index:1;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px 24px;border-top:1px solid var(--line);background:#fff;font:600 15px/1.3 var(--body);color:var(--primary);text-decoration:none}
.srch-all svg{flex:none;transition:transform .2s}
.srch-all:hover svg,.srch-all.on svg{transform:translateX(4px)}
.srch-all:hover,.srch-all.on{background:color-mix(in srgb,var(--primary) 6%,#fff)}
.srch-none{padding:32px 24px 30px;text-align:center}
.srch-none strong{display:block;font:500 22px/1.25 var(--head);color:var(--ink)}
.srch-none p{max-width:44ch;margin:8px auto 0;font:400 14.5px/1.55 var(--body);color:var(--on-variant)}
.srch-none a{display:inline-flex;align-items:center;gap:8px;min-height:44px;margin-top:16px;padding:0 20px;border-radius:999px;background:var(--primary);color:#fff;font:600 14px var(--body);text-decoration:none}
.srch-live{position:absolute;width:1px;height:1px;margin:-1px;overflow:hidden;clip:rect(0 0 0 0)}
.srch-in{animation:srch-in .32s cubic-bezier(.2,.8,.2,1) both;animation-delay:calc(var(--i,0) * 22ms)}
.srch.calm .srch-res .srch-in{animation:none}
@keyframes srch-in{from{opacity:0;transform:translateY(6px)}}
@media (min-width:860px){
.srch-res.two{display:grid;grid-template-columns:minmax(0,1fr) 304px;grid-template-rows:auto 1fr;grid-template-areas:"prod cats" "prod serv"}
.two>.srch-prod{grid-area:prod;border-top:0}
.two>.srch-catsec{grid-area:cats}
.two>.srch-serv{grid-area:serv}
.two>.srch-catsec,.two>.srch-serv{border-left:1px solid var(--line);background:color-mix(in srgb,var(--ink) 2.5%,#fff)}
.two>.srch-catsec{border-top:0}
.two>.srch-serv:not(:only-child){border-top:1px solid var(--line)}
.two .srch-cats{flex-direction:column;gap:0;padding:0}
.two .srch-cat{justify-content:space-between;min-height:40px;padding:0 24px;border:0;border-radius:0;background:none;font-size:15px;white-space:normal}
.two .srch-cat:hover,.two .srch-cat.on{background:color-mix(in srgb,var(--ink) 5%,#fff)}
.two .srch-cat.on{box-shadow:inset 3px 0 var(--primary)}
.two .srch-serv .srch-item{grid-template-columns:40px minmax(0,1fr);align-items:start;gap:12px;padding-block:8px}
.two .srch-serv .srch-tile{grid-row:span 2;width:40px;height:40px}
.two .srch-serv .srch-name{font-size:14px}
.two .srch-serv .srch-item{row-gap:4px}
.two .srch-serv .srch-side{grid-column:2;grid-row:2;align-items:flex-start}
.two .srch-serv .srch-price{font-size:16px}
}
@media (max-width:639.98px){
.srch{padding:0}
.srch-box{width:100%;height:100%;max-height:none;border-radius:0;transform:translateY(24px)}
.srch-bar{height:64px;gap:10px;padding:0 14px 0 16px}
.srch-input{font-size:17px}
.srch-esc{display:none}.srch-cancel{display:block}
.srch-head,.srch-chips,.srch-cats,.srch-item,.srch-all,.srch-opt{padding-inline:16px}
.srch-opt small{display:none}
.srch-cats{flex-wrap:nowrap;overflow-x:auto;scrollbar-width:none;padding-bottom:6px}
.srch-cats::-webkit-scrollbar{display:none}
.srch-item{grid-template-columns:52px minmax(0,1fr) auto;gap:12px}
.srch-tile{width:52px;height:52px}
.srch-name{font-size:14px}
.srch-price{font-size:17px}
.srch-all{padding-bottom:calc(16px + env(safe-area-inset-bottom,0px))}
}
@media (prefers-reduced-motion:reduce){.srch-dim,.srch-box{transition:none}.srch-in{animation:none}.srch.busy .srch-load::after{animation-duration:2.4s}}
''';

/// The box's behavior, after the page script (`window.vinabikeMeasure`).
/// The magnifier, «/» or Ctrl/⌘ K open it; Esc, the dim or «Cancelar» close
/// it and give the focus back. It reads `/buscar?q=` 140 ms after the last
/// letter, one request at a time (the previous one is aborted) and each
/// answer kept for the visit. The arrows walk the suggestions and Enter
/// opens the one marked, or `/productos?q=` with the words. The last six
/// searches stay in this browser only.
const searchOverlayScript = r'''
(function () {
  var root = document.querySelector('[data-search]');
  if (!root) return;
  var box = root.querySelector('.srch-box'), form = root.querySelector('form');
  var input = root.querySelector('.srch-input'), body = root.querySelector('[data-search-body]');
  var clear = root.querySelector('[data-search-clear]'), live = root.querySelector('[data-search-live]');
  var icons = {};
  var tpl = root.querySelector('[data-search-icons]');
  if (tpl && tpl.content) tpl.content.querySelectorAll('[data-icon]').forEach(function (e) { icons[e.dataset.icon] = e.innerHTML; });
  var recentKey = 'vb-search-recent', cache = {}, timer = null, opener = null, last = '', shown = null;
  // Where the suggestions come from: the service's own origin when the page
  // names it (data-api), so a keystroke is not relayed by Firebase Hosting
  // (~200 ms each, 2026-10-25). Its connection opens when the box does.
  var api = root.dataset.api || '', warmed = false;
  function warm() {
    if (warmed || !api) return;
    warmed = true;
    var link = document.createElement('link');
    link.rel = 'preconnect'; link.href = api; link.crossOrigin = 'anonymous';
    document.head.appendChild(link);
  }
  // A search left showing nothing goes to the store's «Búsquedas»
  // (`vinabikeSearchMiss`): after a moment without typing, or when the
  // visitor closes the box or asks by WhatsApp.
  var missTimer = null, shownEmpty = null;
  function miss(q) { if (q && window.vinabikeSearchMiss) window.vinabikeSearchMiss(q); }
  // «Incluir agotados», when the store offers it; this browser remembers it.
  var opt = root.querySelector('[data-search-opt]'), out = root.querySelector('[data-search-out]'), outKey = 'vb-search-agotados';
  if (out) { try { out.checked = localStorage.getItem(outKey) === '1'; } catch (e) { /* off */ } }
  function withOut() { return !!(out && out.checked); }

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function fold(c) { return c.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase(); }
  // The words that only join others ask nothing of the search
  // (`get_public_products_without_inventory_reservations`), nor are they
  // marked.
  var joining = ['de', 'del', 'la', 'las', 'el', 'los', 'lo', 'para', 'con', 'en', 'un', 'una', 'unos', 'unas', 'por', 'al', 'mi', 'su', 'que'];
  function words(q) { return fold(q).split(/[^a-z0-9ñ]+/).filter(function (w) { return w.length > 1 && joining.indexOf(w) < 0; }); }
  // The searched words in bold, found without accents or case.
  function marked(text, q) {
    var ws = words(q), folded = '';
    for (var i = 0; i < text.length; i++) folded += fold(text[i]).charAt(0) || ' ';
    var on = new Array(text.length);
    ws.forEach(function (w) {
      var at = 0, k;
      while ((k = folded.indexOf(w, at)) >= 0) { for (var j = k; j < k + w.length; j++) on[j] = true; at = k + w.length; }
    });
    var out = '', open = false;
    for (var n = 0; n < text.length; n++) {
      if (on[n] && !open) { out += '<mark>'; open = true; }
      if (!on[n] && open) { out += '</mark>'; open = false; }
      out += esc(text[n]);
    }
    return out + (open ? '</mark>' : '');
  }
  function recents() { try { var v = JSON.parse(localStorage.getItem(recentKey) || '[]'); return Array.isArray(v) ? v.slice(0, 6) : []; } catch (e) { return []; } }
  function remember(q) {
    q = q.trim(); if (q.length < 2) return;
    var list = recents().filter(function (x) { return fold(x) !== fold(q); });
    list.unshift(q);
    try { localStorage.setItem(recentKey, JSON.stringify(list.slice(0, 6))); } catch (e) { /* only this visit */ }
  }
  function track(name, params) { var m = window.vinabikeMeasure; if (m && m.track) m.track(name, params); }

  // The header's own categories, in its order and as the editor names them:
  // the mega menu's sections and the dropdowns' first rows.
  function menuCategories() {
    var seen = {}, out = [];
    document.querySelectorAll('header.top .mega-more[href], header.top .drop-item.strong[href]:not(.drop-all)').forEach(function (a) {
      var href = a.getAttribute('href') || '', label = a.dataset.label || (a.querySelector('b') || a).textContent || '';
      var name = label.replace(/\s+/g, ' ').trim();
      if (!name || href.indexOf('/productos/categoria/') < 0 || href.indexOf('?') >= 0 || seen[href] || out.length >= 10) return;
      seen[href] = true; out.push({ name: name, path: href });
    });
    return out;
  }

  function options() { return Array.prototype.slice.call(body.querySelectorAll('[role=option]')); }
  function mark(index) {
    var all = options();
    all.forEach(function (o, i) { o.classList.toggle('on', i === index); o.setAttribute('aria-selected', i === index ? 'true' : 'false'); });
    var on = all[index];
    if (on) { input.setAttribute('aria-activedescendant', on.id); on.scrollIntoView({ block: 'nearest' }); }
    else input.removeAttribute('aria-activedescendant');
  }
  function current() { var all = options(); for (var i = 0; i < all.length; i++) if (all[i].classList.contains('on')) return i; return -1; }
  function paint(html) {
    body.innerHTML = html;
    // New suggestions start at their top, not where the last ones were left.
    body.scrollTop = 0;
    options().forEach(function (o, i) { o.id = 'srch-o' + i; o.setAttribute('aria-selected', 'false'); });
    input.setAttribute('aria-expanded', options().length ? 'true' : 'false');
    input.removeAttribute('aria-activedescendant');
  }

  function empty() {
    var html = '', i = 0, list = recents(), cats = menuCategories();
    if (list.length) {
      html += '<section class="srch-sec"><p class="srch-head">Búsquedas recientes<button type="button" data-search-forget>Borrar</button></p><div class="srch-chips">';
      list.forEach(function (q) { html += '<a class="srch-chip srch-in" style="--i:' + (i++) + '" role="option" data-q="' + esc(q) + '" href="/productos?q=' + encodeURIComponent(q) + '">' + (icons.history || '') + esc(q) + '</a>'; });
      html += '</div></section>';
    }
    if (cats.length) {
      html += '<section class="srch-sec"><p class="srch-head">Explora la tienda</p><div class="srch-chips">';
      cats.forEach(function (c) { html += '<a class="srch-chip srch-in" style="--i:' + (i++) + '" role="option" href="' + esc(c.path) + '">' + esc(c.name) + '</a>'; });
      html += '</div></section>';
    }
    paint(html);
  }

  function item(p, q, i, service, n) {
    var tile = service
      ? '<span class="srch-tile tool">' + (icons.tool || '') + '</span>'
      : '<span class="srch-tile">' + (p.img ? '<img src="' + esc(p.img) + '" alt="" decoding="async">' : (icons.bike || '')) + '</span>';
    return '<a class="srch-item srch-in" style="--i:' + i + '" role="option" href="' + esc(p.path) + '" data-item="' + esc(p.name) + '" data-item-id="' + esc(p.id || '') + '" data-price="' + (p.value || 0) + '" data-index="' + n + '">' + tile +
      '<span class="srch-text">' + (p.brand ? '<span class="srch-brand">' + esc(p.brand) + '</span>' : '') + '<span class="srch-name">' + marked(p.name, q) + '</span></span>' +
      '<span class="srch-side">' + (p.price ? '<span class="srch-price">' + esc(p.price) + '</span>' : '') + (p.out ? '<span class="srch-out">Agotado</span>' : '') + '</span></a>';
  }

  // A refined list replaces the one shown without entering again.
  function results(d) {
    root.classList.toggle('calm', !!body.querySelector('.srch-res'));
    var q = d.q, i = 0, cats = '', prods = '', servs = '', html;
    if (d.categories && d.categories.length) {
      cats = '<section class="srch-sec srch-catsec"><p class="srch-head">Categorías</p><div class="srch-cats">';
      d.categories.forEach(function (c) { cats += '<a class="srch-cat srch-in" style="--i:' + (i++) + '" role="option" href="' + esc(c.path) + '"><span>' + marked(c.name, q) + '</span><b>' + c.count + '</b></a>'; });
      cats += '</div></section>';
    }
    if (d.products && d.products.length) {
      prods = '<section class="srch-sec srch-prod"><p class="srch-head">Productos</p>';
      d.products.forEach(function (p, n) { prods += item(p, q, i++, false, n); });
      prods += '</section>';
    }
    if (d.services && d.services.length) {
      servs = '<section class="srch-sec srch-serv"><p class="srch-head">En el taller</p>';
      d.services.forEach(function (p, n) { servs += item(p, q, i++, true, n); });
      servs += '</section>';
    }
    clearTimeout(missTimer);
    shownEmpty = null;
    if (!cats && !prods && !servs) {
      shownEmpty = q;
      missTimer = setTimeout(function () { if (input.value.trim() === q) miss(q); }, 1500);
      var wa = document.querySelector('a[href*="wa.me/"], a[href*="api.whatsapp.com"]'), waHref = '';
      // The store's WhatsApp, with the search as the message.
      // (encodeURIComponent: WhatsApp shows a «+» as written.)
      if (wa) {
        var base = wa.getAttribute('href').replace(/([?&])text=[^&]*&?/, '$1').replace(/[?&]$/, '');
        waHref = base + (base.indexOf('?') >= 0 ? '&' : '?') + 'text=' + encodeURIComponent((root.dataset.askMissing || '').replace('{q}', q));
      }
      // Out of stock may be what they look for, when the store offers it.
      var inOut = out && !out.checked;
      html = '<div class="srch-none srch-in"><strong>No encontramos «' + esc(q) + '»</strong><p>' +
        (inOut ? 'Puede que hoy no tenga stock: búscalo también entre los agotados. ' : '') +
        'Revisa cómo se escribe o prueba con otra palabra. Si no lo ves, pregúntanos: te ayudamos a encontrarlo.</p>' +
        (inOut ? '<button type="button" data-search-include>Buscar en los agotados</button>' : '') +
        (wa ? '<a href="' + esc(waHref) + '" target="_blank" rel="noopener" data-search-ask>Preguntar por WhatsApp</a>' : '<a href="/contacto">Escríbenos</a>') + '</div>';
      live.textContent = 'Sin resultados para ' + q;
    } else {
      // On a wide box the products take the left and the rest the right.
      html = '<div class="srch-res' + (prods && (cats || servs) ? ' two' : '') + '">' + cats + prods + servs + '</div>';
      live.textContent = (d.total || 0) + ' productos para ' + q;
    }
    if (d.total > 0) html += '<a class="srch-all" role="option" href="' + esc(d.all) + '" data-all><span>Ver ' + (d.total === 1 ? 'el producto' : 'los ' + d.total + ' productos') + ' para «' + esc(q) + '»</span>' + (icons.go || '') + '</a>';
    paint(html);
  }

  function typed() { return input.value.trim() + (withOut() ? '|agotados' : ''); }
  // The longest search already answered that what is typed continues
  // («cade» while «caden» is on its way), with the same «Incluir agotados».
  function closest() {
    var cur = typed(), flag = cur.slice(-9) === '|agotados', q = fold(flag ? cur.slice(0, -9) : cur), best = null;
    if (q.length < 2) return null;
    Object.keys(cache).forEach(function (k) {
      var kf = k.slice(-9) === '|agotados', kq = fold(kf ? k.slice(0, -9) : k);
      if (kf === flag && kq.length >= 2 && q.indexOf(kq) === 0 && (!best || kq.length > best.length)) best = { key: k, length: kq.length };
    });
    return best && best.key;
  }
  function show(key) { shown = key; results(cache[key]); }
  function search() {
    var q = input.value.trim(), agotados = withOut(), key = q + (agotados ? '|agotados' : '');
    clearTimeout(missTimer);
    clear.hidden = !input.value;
    if (opt) opt.hidden = q.length < 2;
    if (key === last) return;
    last = key;
    clearTimeout(timer);
    if (q.length < 2) { shown = null; root.classList.remove('busy'); empty(); return; }
    if (cache[key]) { show(key); root.classList.remove('busy'); return; }
    // Meanwhile the list follows the typing with what is already answered,
    // instead of waiting for the visitor to stop (until 2026-10-25 only the
    // answer to exactly what was typed was drawn, and the one before it was
    // cancelled).
    var near = closest();
    if (near && near !== shown) show(near);
    root.classList.add('busy');
    timer = setTimeout(ask, 90);
  }
  // One question at a time, always about what is typed now: a burst of
  // keystrokes is not a queue of searches the server answers in order (it
  // takes four reads at the database at once, DatabaseGate).
  var asking = null;
  function ask() {
    if (asking) return;
    var key = typed(), flag = key.slice(-9) === '|agotados', q = flag ? key.slice(0, -9) : key;
    if (q.length < 2 || cache[key]) { if (cache[key] && shown !== key) show(key); root.classList.remove('busy'); return; }
    asking = key;
    function done(d) {
      asking = null;
      if (d) {
        cache[key] = d;
        if (typed() === key || (closest() === key && shown !== key)) show(key);
      }
      if (typed() !== key) ask(); else root.classList.remove('busy');
    }
    fetch(api + '/buscar?q=' + encodeURIComponent(q) + (flag ? '&stock=all' : '')).then(function (r) { return r.ok ? r.json() : null; }).then(done, function () { done(null); });
  }

  function open(from) {
    if (!root.hidden) return;
    warm();
    opener = from || document.activeElement;
    root.hidden = false;
    document.documentElement.classList.add('srch-lock');
    last = null; search();
    void box.offsetWidth;
    root.classList.add('on');
    setTimeout(function () { input.focus(); input.select(); }, 30);
  }
  function close() {
    if (root.hidden) return;
    if (shownEmpty && input.value.trim() === shownEmpty) miss(shownEmpty);
    root.classList.remove('on', 'busy');
    document.documentElement.classList.remove('srch-lock');
    setTimeout(function () { if (!root.classList.contains('on')) root.hidden = true; }, 260);
    if (opener && opener.focus) opener.focus();
  }
  function go(el) {
    var q = input.value.trim();
    if (el.dataset.q) { remember(el.dataset.q); return; }
    if (q.length > 1) remember(q);
    if (el.hasAttribute('data-all')) track('search', { search_term: q });
    else if (el.dataset.item) track('select_item', { item_list_id: 'buscador', item_list_name: 'Buscador', items: [{ item_id: el.dataset.itemId || el.dataset.item, item_name: el.dataset.item, price: Number(el.dataset.price || 0), index: Number(el.dataset.index || 0) }] });
  }

  document.addEventListener('click', function (e) {
    var t = e.target.closest('[data-search-open]');
    if (t) { e.preventDefault(); open(t); }
  });
  // The pointer on the magnifier: the connection opens before the click.
  document.addEventListener('pointerover', function (e) {
    if (e.target.closest && e.target.closest('[data-search-open]')) warm();
  }, { passive: true });
  root.addEventListener('click', function (e) {
    if (e.target.closest('[data-search-ask]')) miss(shownEmpty);
    if (e.target.closest('[data-search-close]')) { close(); return; }
    if (e.target.closest('[data-search-clear]')) { input.value = ''; search(); input.focus(); return; }
    if (e.target.closest('[data-search-include]')) { out.checked = true; out.dispatchEvent(new Event('change')); return; }
    if (e.target.closest('[data-search-forget]')) { try { localStorage.removeItem(recentKey); } catch (x) { /* nothing kept */ } empty(); input.focus(); return; }
    var o = e.target.closest('[role=option]');
    if (o) go(o);
  });
  input.addEventListener('input', search);
  if (out) out.addEventListener('change', function () {
    try { localStorage.setItem(outKey, out.checked ? '1' : '0'); } catch (e) { /* only this visit */ }
    search();
    input.focus();
  });
  body.addEventListener('error', function (e) {
    var t = e.target;
    if (t && t.tagName === 'IMG' && t.parentNode) t.parentNode.innerHTML = icons.bike || '';
  }, true);
  form.addEventListener('submit', function (e) {
    var q = input.value.trim();
    var on = options()[current()];
    if (on) { e.preventDefault(); go(on); location.href = on.getAttribute('href'); return; }
    if (q.length < 2) { e.preventDefault(); return; }
    remember(q);
    track('search', { search_term: q });
  });
  root.addEventListener('keydown', function (e) {
    var all = options(), i = current();
    if (e.key === 'Escape') { e.preventDefault(); close(); }
    else if (e.key === 'ArrowDown' && all.length) { e.preventDefault(); mark(i + 1 >= all.length ? 0 : i + 1); }
    else if (e.key === 'ArrowUp' && all.length) { e.preventDefault(); mark(i <= 0 ? all.length - 1 : i - 1); }
    else if (e.key === 'Tab') {
      // The focus stays in the box while it is open.
      var f = Array.prototype.slice.call(box.querySelectorAll('input,button:not([hidden]),a[href]')).filter(function (x) { return x.offsetParent !== null; });
      if (!f.length) return;
      var first = f[0], end = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); end.focus(); }
      else if (!e.shiftKey && document.activeElement === end) { e.preventDefault(); first.focus(); }
    }
  });
  document.addEventListener('keydown', function (e) {
    var t = e.target, typing = t && (t.isContentEditable || /^(input|textarea|select)$/i.test(t.tagName));
    if ((e.key === 'k' || e.key === 'K') && (e.metaKey || e.ctrlKey)) { e.preventDefault(); root.hidden ? open(null) : close(); }
    else if (e.key === '/' && !typing && root.hidden) { e.preventDefault(); open(null); }
  });
})();
''';
