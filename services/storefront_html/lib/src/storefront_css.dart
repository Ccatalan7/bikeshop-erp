/// The storefront's stylesheet. Colors and fonts come from the editor's theme
/// (`theme_primary_color`, `theme_accent_color`, `theme_heading_font`,
/// `theme_body_font` through `WebsiteFontRegistry`); the fonts and the logo
/// are the files Firebase Hosting already serves for the Flutter store.
///
/// Header, footer and theme are drawn twice (here and in Flutter) only until
/// phase 2 moves the editor canvas to this renderer, so they follow the
/// Flutter store's: white header with uppercase navigation, slate footer
/// (`PublicStoreTheme.textPrimary`), the catalog's navy hero band.
String storefrontCss({
  required String primary,
  required String accent,
  required String headingFont,
  required String bodyFont,
}) =>
    '''
@font-face{font-family:Oswald;src:url(/assets/assets/fonts/Oswald-wght.ttf) format("truetype");font-weight:200 700;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Regular.ttf) format("truetype");font-weight:400;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Medium.ttf) format("truetype");font-weight:500;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-SemiBold.ttf) format("truetype");font-weight:600;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Bold.ttf) format("truetype");font-weight:700;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-ExtraBold.ttf) format("truetype");font-weight:800 900;font-display:swap}
:root{--primary:$primary;--accent:$accent;--ink:#1e293b;--muted:#5b6b7f;--faint:#94a3b8;--line:#e2e8f0;--soft:#f4f6f9;--ok:#15803d;--bad:#b42318;--foot:#1e293b;--r:14px;
--head:"$headingFont","Arial Narrow",Arial,sans-serif;--body:"$bodyFont","Segoe UI",Roboto,Arial,sans-serif}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:#fff;color:var(--ink);font:400 17px/1.55 var(--body)}
img{max-width:100%;display:block}a{color:var(--primary)}
.wrap{max-width:1280px;margin:0 auto;padding-inline:24px}
.skip{position:absolute;left:-999px}.skip:focus{left:16px;top:8px;z-index:20;background:#fff;padding:8px 12px}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}
a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:3px solid var(--accent);outline-offset:2px}

/* Header */
.top{position:sticky;top:0;z-index:10;background:#fff;border-bottom:1px solid var(--line)}
.banner{margin:0;padding:7px 16px;background:var(--primary);color:#fff;text-align:center;font:600 13px/1.3 var(--body);letter-spacing:.04em}
.bar{display:flex;align-items:center;gap:28px;height:68px}
.logo img{height:34px;width:auto}
.logo-name{font:700 24px var(--head);text-transform:uppercase;color:var(--ink);text-decoration:none}
.menu{flex:1;display:flex;align-items:center}.menu-toggle{position:absolute;opacity:0;pointer-events:none}.menu-button{display:none}.menu-login{display:none}
.menu nav>ul{display:flex;gap:24px;list-style:none;margin:0;padding:0}
.menu nav>ul>li{position:relative}
.menu nav>ul>li>a{display:block;padding:24px 0 22px;font:500 13.5px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;color:#334155;text-decoration:none;border-bottom:2px solid transparent}
.menu nav>ul>li>a:hover,.menu nav>ul>li>a[aria-current]{color:var(--ink);border-bottom-color:var(--ink)}
.has-sub>a::after{content:"";display:inline-block;width:6px;height:6px;margin-left:7px;border:solid currentColor;border-width:0 1.6px 1.6px 0;transform:translateY(-3px) rotate(45deg)}
.sub{display:none;position:absolute;top:100%;left:-18px;min-width:230px;list-style:none;margin:0;padding:10px;background:#fff;border:1px solid var(--line);border-radius:12px;box-shadow:0 18px 40px rgba(15,23,42,.12)}
.has-sub:hover .sub,.has-sub:focus-within .sub{display:block}
.sub a{display:block;padding:9px 10px;border-radius:8px;color:var(--ink);text-decoration:none;font-size:15px}.sub a:hover,.sub a[aria-current]{background:var(--soft)}
.tools{display:flex;align-items:center;gap:18px;color:var(--ink)}.tools>a{color:inherit;display:flex;align-items:center}
.cart-link{position:relative}
.cart-count{position:absolute;top:-8px;right:-10px;min-width:19px;height:19px;padding:0 5px;border-radius:999px;background:var(--accent);color:#fff;font:700 11px/19px var(--body);text-align:center}
.login{gap:8px;border:1px solid #cbd5e1;border-radius:8px;padding:9px 14px;font:600 12.5px/1 var(--body)!important;letter-spacing:.06em;text-transform:uppercase;text-decoration:none}
.login:hover{border-color:var(--ink)}

/* Breadcrumbs */
.crumbs ol{display:flex;flex-wrap:wrap;gap:6px;list-style:none;margin:0;padding:18px 0 6px;font-size:14px;color:var(--muted)}
.crumbs li+li::before{content:"/";margin-right:6px;color:#b6c0cc}
.crumbs a{color:var(--muted);text-decoration:none}.crumbs a:hover{color:var(--primary);text-decoration:underline}
.crumbs [aria-current] span{color:var(--ink)}

/* Product */
.product{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(0,1fr);gap:56px;padding-block:18px 56px;align-items:start}
.stage{margin:0;background:var(--soft);border-radius:var(--r);aspect-ratio:1/1;display:grid;place-items:center;overflow:hidden}
.stage img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply;padding:6%}
.thumbs{display:flex;gap:10px;list-style:none;margin:12px 0 0;padding:0;overflow-x:auto}
.thumbs button{border:1.5px solid transparent;border-radius:10px;padding:0;background:var(--soft);cursor:pointer;width:76px;height:76px}
.thumbs button[aria-current]{border-color:var(--primary)}
.thumbs img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.buy{position:sticky;top:92px}
.brand{margin:0 0 8px;font:600 13px/1 var(--body);letter-spacing:.16em;text-transform:uppercase;color:var(--accent)}
h1{margin:0;font:600 clamp(28px,3.1vw,40px)/1.06 var(--head);text-transform:uppercase;letter-spacing:.01em;text-wrap:balance}
.ids{display:flex;gap:16px;flex-wrap:wrap;margin:12px 0 0;color:var(--muted);font-size:14px}
.price-row{margin:26px 0 6px;display:flex;align-items:baseline;gap:14px;flex-wrap:wrap}
.price{margin:0;font:600 42px/1 var(--head);color:var(--primary);font-variant-numeric:tabular-nums}
.tax{margin:0;color:var(--muted);font-size:14px}
.stock{display:inline-flex;align-items:center;gap:8px;margin:6px 0 0;font-weight:600;font-size:15px}
.stock span{width:8px;height:8px;border-radius:50%;background:currentColor}
.stock.ok{color:var(--ok)}.stock.out{color:var(--bad)}
.highlights{display:grid;grid-template-columns:1fr 1fr;gap:1px;margin:24px 0 0;background:var(--line);border:1px solid var(--line);border-radius:12px;overflow:hidden}
.highlights div{background:#fff;padding:14px 16px}
.highlights dt{font-size:13px;color:var(--muted)}.highlights dd{margin:2px 0 0;font-weight:700;font-size:16px}
.to-sheet{display:inline-block;margin-top:10px;font-weight:600;font-size:15px}
.cart{display:flex;gap:12px;margin-top:26px}
.qty input{width:84px;height:54px;border:1px solid var(--line);border-radius:12px;font:600 17px var(--body);text-align:center}
button.primary{flex:1;height:54px;border:0;border-radius:12px;background:var(--primary);color:#fff;font:600 15px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;cursor:pointer}
button.primary:hover{filter:brightness(1.12)}button.primary:disabled{background:#c7cfd9;cursor:not-allowed}
.cart-note{display:flex;flex-wrap:wrap;align-items:center;gap:6px 14px;margin:12px 0 0;padding:12px 14px;border-radius:12px;background:#ecfdf3;color:#14532d;font-size:15px}
.cart-note[data-state=max]{background:#fff7ed;color:#7c2d12}.cart-note[data-state=error]{background:#fef3f2;color:var(--bad)}
.cart-note a{font-weight:700;color:inherit}
.secondary{display:flex;align-items:center;justify-content:center;height:50px;margin-top:10px;border:1.5px solid var(--primary);border-radius:12px;color:var(--primary);font:600 14px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;text-decoration:none}
.promises{list-style:none;margin:26px 0 0;padding:0;border-top:1px solid var(--line)}
.promises li{display:grid;gap:2px;padding:14px 0;border-bottom:1px solid var(--line);font-size:15px}
.promises span{color:var(--muted)}
.details{padding-block:56px;border-top:1px solid var(--line)}
h2{margin:0 0 26px;font:600 30px/1.1 var(--head);text-transform:uppercase;letter-spacing:.02em}
.description{max-width:70ch;margin-bottom:34px;font-size:18px}.description p{margin:0 0 14px}
.sheet{columns:2 420px;column-gap:48px}
.group{break-inside:avoid;margin-bottom:30px}
.group h3{margin:0 0 6px;font:600 14px/1 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--accent)}
.group dl{margin:0}.group dl div{display:grid;grid-template-columns:minmax(150px,40%) 1fr;gap:16px;padding:12px 0;border-bottom:1px solid var(--line)}
.group dt{color:var(--muted)}.group dt small{display:block;font-size:13px;color:#8693a3;margin-top:2px}
.group dd{margin:0;font-weight:600}.detail{font-weight:400;color:var(--muted)}
.related{padding-block:48px 64px;border-top:1px solid var(--line)}
.related-head{display:flex;align-items:baseline;justify-content:space-between;gap:16px}
.related-head a{font-weight:600}
.buybar{display:none}

/* Product cards (related products and the catalog grid) */
.cards{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:36px 28px;list-style:none;margin:0;padding:0}
.cards.compact{grid-template-columns:repeat(5,minmax(0,1fr));gap:40px 26px}.cards.editorial{grid-template-columns:repeat(3,minmax(0,1fr))}
.card a{display:grid;gap:6px;color:var(--ink);text-decoration:none}
.card .shot{aspect-ratio:1/1;background:#fff;border-bottom:1px solid var(--line);padding:6%;display:grid;place-items:center}
.card .shot img{width:100%;height:100%;object-fit:contain}
.card .maker{margin:6px 0 0;padding:0 16px;font:600 11px/1 var(--body);letter-spacing:.1em;text-transform:uppercase;color:var(--faint)}
.card .name{padding:0 16px;font:700 14.5px/1.3 var(--body);text-transform:uppercase;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.card .p{padding:0 16px;font:800 17px/1.2 var(--body);font-variant-numeric:tabular-nums}
.card a:hover .name{color:var(--primary)}

/* Catalog */
.hero{position:relative;display:grid;align-items:center;min-height:var(--hero,130px);color:#fff;background:linear-gradient(90deg,#0c2234,#315266);overflow:hidden}
.hero img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.hero::after{content:"";position:absolute;inset:0;background:rgba(0,0,0,var(--shade,.35))}
.hero .wrap{position:relative;z-index:1;width:100%;padding-block:24px}
.hero.center .wrap{text-align:center}.hero.center .hero-text{margin-inline:auto}
.hero-text{max-width:720px}
.eyebrow{margin:0 0 12px;font:800 11px/1 var(--body);letter-spacing:.16em;text-transform:uppercase}
.hero h1{margin:0;font:900 clamp(32px,4vw,48px)/.98 var(--body);letter-spacing:.02em;text-transform:uppercase;color:#fff}
.hero-intro{margin:16px 0 0;font-size:16px;line-height:1.5;color:rgba(255,255,255,.92)}
.subcats{border-bottom:1px solid var(--line)}
.subcats ul{display:flex;gap:22px;list-style:none;margin:0;padding:12px 0;overflow-x:auto;scrollbar-width:none}
.subcats a{font:800 11px/1 var(--body);letter-spacing:.07em;text-transform:uppercase;color:#1f2937;text-decoration:none;white-space:nowrap}
.subcats a:hover{color:var(--primary)}
.top .wrap,.catalog.wrap,.hero .wrap,.subcats .wrap{max-width:1560px;padding-inline:28px}.hero .wrap{padding-inline:56px}
.catalog{display:grid;grid-template-columns:236px minmax(0,1fr);gap:40px;padding-block:30px 64px;align-items:start}
.filters{display:grid;gap:4px}
.filters h2,.filters .side-title{margin:0 0 12px;font:700 15px/1 var(--body);text-transform:none;letter-spacing:0}
.search{display:flex;margin-bottom:22px}
.search input{width:100%;height:44px;border:1px solid var(--line);border-radius:10px;padding:0 14px 0 40px;font:500 15px var(--body);background:var(--soft) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' width='18' height='18'%3E%3Ccircle cx='11' cy='11' r='7' fill='none' stroke='%2394a3b8' stroke-width='2'/%3E%3Cpath d='M20 20l-4-4' stroke='%2394a3b8' stroke-width='2' stroke-linecap='round'/%3E%3C/svg%3E") no-repeat 12px center}
.facet{border-top:1px solid var(--line);padding:16px 0}
.facet h2{margin:0 0 10px;font:700 14px/1.2 var(--body);text-transform:none;letter-spacing:0}
.facet ul{list-style:none;margin:0;padding:0;display:grid;gap:6px}
.facet a,.facet label{display:flex;align-items:center;justify-content:space-between;gap:10px;font-size:14px;color:#334155;text-decoration:none;cursor:pointer}
.facet a[aria-current]{font-weight:700;color:var(--ink)}
.facet label span:first-of-type{display:flex;align-items:center;gap:10px}
.facet input[type=checkbox]{width:18px;height:18px;margin:0;accent-color:var(--primary)}
.facet .n{color:var(--faint);font-size:12.5px;font-variant-numeric:tabular-nums}
.facet ul ul{margin-top:6px}
p.n{margin:0 0 10px}
.price-range{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.price-range label{display:grid;gap:4px;font-size:12px;color:var(--muted)}
.price-range input{width:100%;height:40px;border:1px solid var(--line);border-radius:8px;padding:0 10px;font:500 15px var(--body);color:var(--ink);background:#fff}
.apply-now{margin-top:10px;width:100%;height:40px;border:1px solid var(--ink);border-radius:8px;background:#fff;color:var(--ink);font:600 13px var(--body);cursor:pointer}
.apply-now:hover{background:var(--soft)}
.apply{margin-top:8px;height:40px;padding:0 14px;border:1px solid var(--ink);border-radius:8px;background:#fff;color:var(--ink);font:600 13px var(--body);cursor:pointer}
.js .apply{display:none}
.results-head{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px 24px;margin-bottom:6px}
.trail{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 10px;margin:0;padding-left:12px;border-left:3px solid var(--ink);font:600 clamp(18px,2vw,22px)/1.2 var(--body);color:var(--muted)}
.trail a{color:var(--muted);text-decoration:none}.trail a:hover{color:var(--ink)}
.trail span+span::before,.trail a+span::before,.trail a+a::before,.trail a+strong::before{content:"/";margin-right:10px;color:#cbd5e1}
.trail strong{color:var(--ink)}
h1.trail{font-weight:700}
.scope{display:flex;flex-wrap:wrap;gap:4px 10px;margin:-14px 0 20px;font-size:12.5px;color:#475569}.scope a{font-weight:700;text-decoration:none}
.order{display:flex;gap:14px;align-items:center;font-size:13.5px;color:var(--muted)}
.order select{height:36px;border:1px solid var(--line);border-radius:8px;padding:0 10px;font:500 14px var(--body);background:#fff;color:var(--ink)}
.count{margin:0 0 22px;font-size:13.5px;color:var(--muted)}
.notice{margin:0 0 12px;padding:10px 14px;border-radius:8px;background:#fff4e5;color:#7a3e00;font-size:14px}
.empty{padding:64px 0;text-align:center;color:var(--muted);font-size:14px}.empty p{margin:0 0 8px}.empty-title{font-size:17px;font-weight:500;color:#475569}
.pager{display:flex;justify-content:center;flex-wrap:wrap;gap:8px;margin-top:44px}
.pager a,.pager span{min-width:40px;height:40px;display:grid;place-items:center;padding:0 12px;border:1px solid var(--line);border-radius:8px;color:var(--ink);text-decoration:none;font-weight:600}
.pager [aria-current]{background:var(--ink);border-color:var(--ink);color:#fff}
.pager .gap{border:0;min-width:20px;padding:0}
.filters-check{position:absolute;opacity:0;pointer-events:none}.filters-toggle{display:none}

/* Footer */
.foot{background:var(--foot);color:#cbd5e1;padding-top:56px;margin-top:8px;font-size:15px}
.foot-grid{display:grid;grid-template-columns:minmax(220px,1.4fr) repeat(auto-fit,minmax(160px,1fr));gap:36px}
.foot p{margin:0 0 6px}.foot a{color:#e2e8f0;text-decoration:none}.foot a:hover{color:#fff;text-decoration:underline}
.foot-logo img{height:44px;width:auto;filter:brightness(0) invert(1)}
.foot-brand p{margin-top:16px;line-height:1.6}
.foot-name{font:700 26px var(--head);color:#fff;text-transform:uppercase}
.foot-title{font:700 15px/1 var(--body)!important;color:#fff;margin-bottom:16px!important}
.foot ul{list-style:none;margin:0;padding:0;display:grid;gap:9px}
.socials{display:flex!important;gap:14px!important;margin-top:18px!important}
.socials a{display:grid;place-items:center;width:38px;height:38px;border-radius:50%;background:rgba(255,255,255,.08);color:#fff}
.socials a:hover{background:rgba(255,255,255,.18)}
.contact li{display:grid;grid-template-columns:20px 1fr;gap:10px;align-items:start}.contact svg{margin-top:2px;color:#94a3b8}
.payments{margin-top:44px;text-align:center}
.payments p{font-size:11px;letter-spacing:.06em;color:#94a3b8;margin-bottom:14px}
.payments ul{display:flex;justify-content:center;flex-wrap:wrap;gap:12px}
.pay-badge{display:grid;place-items:center;height:34px;padding:4px 10px;border-radius:6px;background:#fff}
.pay-badge img{height:22px;width:auto}
.pay-chip{display:inline-flex;align-items:center;gap:8px;height:34px;padding:0 12px;border-radius:6px;border:1px solid rgba(255,255,255,.24);background:rgba(255,255,255,.08);color:#fff;font-size:12.5px;font-weight:600}
.legal{margin:36px auto 0!important;padding-block:20px;border-top:1px solid rgba(255,255,255,.12);font-size:13px;color:#94a3b8;text-align:center}
.chat-fab{position:fixed;right:20px;bottom:20px;z-index:9;display:grid;place-items:center;width:58px;height:58px;border-radius:16px;background:#111827;color:#fff;box-shadow:0 10px 30px rgba(15,23,42,.3)}
.chat-fab:hover{background:#000}
.mark-note{position:fixed;left:50%;transform:translateX(-50%);bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:30;max-width:calc(100% - 32px);padding:12px 16px;border-radius:10px;background:#1f2328;color:#fff;font:500 14px/1.4 var(--body);box-shadow:0 6px 24px rgba(0,0,0,.25);text-align:center}
.holding{min-height:100vh;display:grid;place-content:center;gap:8px;padding:24px;text-align:center}
.notfound{padding-block:72px 96px;max-width:640px}.notfound p{color:var(--muted)}
.notfound a.primary-link{display:inline-block;margin-top:18px;padding:14px 22px;border-radius:12px;background:var(--primary);color:#fff;font-weight:600;text-decoration:none}

@media (min-width:761px){.nav-no-desktop{display:none!important}}
@media (max-width:760px){.nav-no-mobile{display:none!important}}
@media (max-width:1180px){.cards,.cards.compact{grid-template-columns:repeat(3,minmax(0,1fr))}}
@media (max-width:980px){
.product{grid-template-columns:1fr;gap:26px}.buy{position:static}
.catalog{grid-template-columns:1fr;gap:0;padding-top:16px}
.filters-toggle{display:flex;align-items:center;gap:10px;min-height:44px;margin:0;font:500 16px var(--body);color:#334155;cursor:pointer}
.filters-check:focus-visible+.filters-toggle{outline:3px solid var(--accent);outline-offset:2px}
.filters-panel{border-bottom:1px solid var(--line);padding-bottom:8px;margin-bottom:22px}
.filters-check:not(:checked)~.filters{display:none}
.filters-check:checked~.filters{padding-top:12px}
.filters:has(#buscar:target){display:grid;padding-top:12px}
.filters .side-title{display:none}
.facet ul{gap:0}.facet a,.facet label{min-height:40px}
.results-head{align-items:flex-start}.order{flex-wrap:wrap}
}
@media (max-width:760px){
body{font-size:16px}.wrap,.top .wrap,.catalog.wrap,.subcats .wrap{padding-inline:16px}.hero .wrap{padding-inline:22px}
.bar{gap:12px;height:62px}.logo{order:1;margin-right:auto}.logo img{height:28px}.tools{order:2;gap:16px}.tools .login{display:none}
.crumbs ol{flex-wrap:nowrap;overflow-x:auto;white-space:nowrap;scrollbar-width:none;padding-top:12px}.crumbs [aria-current]{display:none}
.menu-button{order:3;display:grid;gap:4px;width:28px;cursor:pointer}
.menu-button span{height:2px;background:var(--ink);border-radius:2px}
.menu-toggle:focus-visible+.menu-button{outline:3px solid var(--accent);outline-offset:4px}
.menu{display:none;position:fixed;inset:62px 0 auto;max-height:calc(100vh - 62px);overflow:auto;background:#fff;border-bottom:1px solid var(--line);padding:8px 16px 20px;flex-direction:column;align-items:stretch}
.menu-toggle:checked~.menu{display:flex}
.menu nav>ul{flex-direction:column;gap:0}.menu nav>ul>li>a{padding:15px 0;border-bottom:1px solid var(--line)}
.menu-login{display:block;margin-top:16px;padding:14px;border:1px solid var(--ink);border-radius:10px;text-align:center;font:600 13px/1 var(--body);letter-spacing:.06em;text-transform:uppercase;color:var(--ink);text-decoration:none}
.sub{position:static;display:block;border:0;box-shadow:none;padding:0 0 8px 12px}.has-sub>a::after{display:none}
.price{font-size:36px}.sheet{columns:1}.group dl div{grid-template-columns:1fr;gap:2px}
.buybar{display:flex;position:fixed;left:0;right:0;bottom:0;z-index:8;gap:14px;align-items:center;padding:10px 16px calc(10px + env(safe-area-inset-bottom,0px));background:#fff;border-top:1px solid var(--line);box-shadow:0 -10px 30px rgba(20,27,36,.08)}
.buybar span{font:600 24px var(--head);color:var(--primary)}.buybar button{height:48px}
body:has(.buybar){padding-bottom:76px}body:has(.buybar) .chat-fab{bottom:90px}
.cards,.cards.compact,.cards.editorial{grid-template-columns:repeat(2,minmax(0,1fr));gap:28px 16px}
.card .maker,.card .name,.card .p{padding:0 4px}
.hero h1{font-size:32px}.hero{min-height:var(--hero-phone,130px)}
.trail{font-size:17px}
.foot-grid{grid-template-columns:1fr 1fr}.foot-brand{grid-column:1/-1}
}
''';
