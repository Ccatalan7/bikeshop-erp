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
:root{--primary:$primary;--accent:$accent;--ink:#1e293b;--on-variant:#475569;--outline-variant:#cbd5e1;--chevron:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M7.41 8.59 12 13.17l4.59-4.58L18 10l-6 6-6-6z'/%3E%3C/svg%3E");--muted:#5b6b7f;--faint:#94a3b8;--line:#e2e8f0;--soft:#f4f6f9;--ok:#15803d;--bad:#b42318;--foot:#1e293b;--r:14px;--c-line:#e8e2d8;--c-2nd:#666d7a;--c-muted:#93989f;--c-soft:#f6f6f6;--c-ok:#10b981;
--head:"$headingFont","Arial Narrow",Arial,sans-serif;--body:"$bodyFont","Segoe UI",Roboto,Arial,sans-serif}
[hidden]{display:none!important}*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:#fff;color:var(--ink);font:400 17px/1.55 var(--body)}
img{max-width:100%;display:block}a{color:var(--primary)}
.wrap{max-width:1280px;margin:0 auto;padding-inline:24px}
.skip{position:absolute;left:-999px}.skip:focus{left:16px;top:8px;z-index:20;background:#fff;padding:8px 12px}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}
a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:3px solid var(--accent);outline-offset:2px}

/* Header */
.top{position:sticky;top:0;z-index:10;background:#fff}
.banner{margin:0;padding:7px 16px;background:var(--primary);color:#fff;text-align:center;font:600 13px/1.3 var(--body);letter-spacing:.04em}
.top .wrap.bar{max-width:none;padding-inline:24px}
.bar{display:flex;align-items:center;height:56px}
.logo{display:flex;align-items:center;flex:none;margin-right:22px}.logo img{display:block;height:38px;width:auto}
.logo-name{font:400 24px var(--head);text-transform:uppercase;color:var(--ink);text-decoration:none}
.menu{flex:1;display:flex;align-items:center;min-width:0}.menu-toggle{position:absolute;opacity:0;pointer-events:none}.menu-button,.menu-sheet,.sheet-scrim{display:none}
.menu>ul{display:flex;gap:24px;list-style:none;margin:0;padding:0}
.menu>ul>li{position:relative;display:flex;align-items:center;height:56px}
.menu>ul>li>a{display:flex;align-items:center;padding:5px 0;font:400 14px/20px var(--body);letter-spacing:.1px;text-transform:uppercase;color:var(--ink);text-decoration:none;border-bottom:2px solid transparent;white-space:nowrap}
.menu>ul>li>a[aria-current]{color:var(--primary);font-weight:600;border-bottom-color:var(--primary)}
.has-sub>a{font-weight:600!important;border-bottom-color:transparent!important;border-radius:4px;transition:background .25s}
.has-sub:hover>a,.has-sub:focus-within>a{background:color-mix(in srgb,var(--primary) 8%,transparent)}
.has-sub>a::after{content:"";width:18px;height:18px;margin-left:4px;background:currentColor;-webkit-mask:var(--chevron) center/18px no-repeat;mask:var(--chevron) center/18px no-repeat;transition:transform .25s}
.has-sub:hover>a::after,.has-sub:focus-within>a::after{transform:rotate(-180deg)}
.sub{display:none;position:absolute;top:100%;left:-18px;min-width:230px;list-style:none;margin:0;padding:10px;background:#fff;border:1px solid var(--line);border-radius:12px;box-shadow:0 18px 40px rgba(15,23,42,.12)}
.has-sub:hover .sub,.has-sub:focus-within .sub{display:block}
.sub a{display:block;padding:9px 10px;border-radius:8px;color:var(--ink);text-decoration:none;font-size:15px}.sub a:hover,.sub a[aria-current]{background:var(--soft)}
.tools{display:flex;align-items:center;gap:2px;margin-left:auto;color:var(--ink)}.tools>a{color:inherit;display:flex;align-items:center;justify-content:center;width:40px;height:40px}.tools>a svg{width:22px;height:22px}
.cart-link{position:relative}
.cart-count{position:absolute;top:-8px;right:-10px;min-width:19px;height:19px;padding:0 5px;border-radius:999px;background:var(--accent);color:#fff;font:700 11px/19px var(--body);text-align:center}
.tools>a.login{width:auto;height:auto;margin-left:10px;gap:8px;border:1.2px solid rgba(203,213,225,.9);border-radius:10px;padding:9px 14px;background:rgba(255,255,255,.92);font:600 13px/18px var(--body)!important;letter-spacing:.15px;text-transform:uppercase;text-decoration:none;white-space:nowrap}
.tools>a.login svg{width:17px;height:17px}
.login:hover{background:rgba(30,41,59,.05)}

/* Product page: product_detail_page.dart and product_spec_sheet_view.dart.
   Its colors are the store theme's commerce roles: text #1e293b, accent the
   primary color, line #e8e2d8, secondary and muted text at 68 % and 48 %. */
.pdp,.details-in,.related{width:min(1420px,calc(100% - 96px));margin-inline:auto}
.pdp{margin-top:30px}
.crumbs ol{display:flex;flex-wrap:wrap;align-items:center;gap:6px 8px;list-style:none;margin:0 0 30px;padding:0}
.crumbs li{display:flex;align-items:center;gap:8px}
.crumbs li+li::before{content:"/";font:600 13px/1 var(--body);color:var(--c-muted)}
.crumbs a{font:600 14px/1.4 var(--body);color:var(--primary);text-decoration:none}.crumbs a:hover{text-decoration:underline}
.crumbs .plain{font:400 16px/1.4 var(--body);color:var(--c-muted)}
.crumbs [aria-current] span{font:500 14px/1.4 var(--body);color:var(--c-muted)}
.product{display:grid;grid-template-columns:minmax(0,54fr) minmax(0,46fr);column-gap:56px;align-items:start}
.gallery{container-type:inline-size;min-width:0}
.stage{position:relative;display:grid;place-items:center;height:clamp(400px,82cqw,540px);margin:0;background:#fff;color:var(--c-muted)}
.stage img{position:absolute;inset:4px;width:calc(100% - 8px);height:calc(100% - 8px);object-fit:contain}
.thumbs{display:flex;gap:18px;list-style:none;margin:20px 0 0;padding:0;overflow-x:auto}
.thumbs button{display:block;width:92px;height:92px;padding:8px;border:1px solid var(--c-line);border-radius:4px;background:#fff;cursor:pointer}
.thumbs button[aria-current]{padding:7px;border:2px solid var(--primary);background:color-mix(in srgb,var(--primary) 4%,#fff)}
.thumbs img{width:100%;height:100%;object-fit:contain}
.buy{container-type:inline-size;min-width:0}
.buy h1{margin:3px 0 0;font:400 34px/1.2 var(--head);letter-spacing:.2px;text-transform:uppercase;color:var(--ink);overflow-wrap:anywhere}
.buy hr{margin:24px 0;border:0;border-top:1px solid var(--c-line)}
.price{margin:0;font:400 40px/.95 var(--head);color:var(--primary);font-variant-numeric:tabular-nums}
.tax{margin:6px 0 0;font-size:13px;line-height:1.4;color:var(--c-2nd)}
.highlights{display:grid;grid-template-columns:1fr 1fr;gap:1px;margin:24px 0 0;border:1px solid var(--c-line);border-radius:8px;background:var(--c-line);overflow:hidden}
.highlights div{display:flex;flex-direction:column-reverse;justify-content:flex-end;gap:3px;padding:12px 16px 13px;background:var(--c-soft)}
.highlights .wide{grid-column:1/-1}
.highlights dd{margin:0;font:400 16.5px/1.3 var(--head);color:var(--ink)}
.highlights dt{font:500 12.5px/1.3 var(--body);color:var(--c-2nd)}
@container (max-width:299px){.highlights{grid-template-columns:1fr}}
.to-sheet{display:inline-flex;align-items:center;gap:8px;min-height:44px;margin-top:6px;padding:10px 4px;font:700 13px/1.2 var(--body);color:var(--primary);text-decoration:none}
.to-sheet:hover{background:color-mix(in srgb,var(--primary) 6%,transparent)}
.to-sheet+hr{margin-top:6px}.buy h1+hr{margin-top:22px}
.buy hr+.stock-row{margin-top:-2px}
.stock-row{display:flex;align-items:center;gap:16px}
.stock{display:flex;align-items:center;gap:12px;margin:0;font:700 14px/1.4 var(--body)}
.stock span{width:6px;height:6px;border-radius:50%;background:currentColor}
.stock.ok{color:var(--c-ok)}.stock.out{color:var(--c-2nd)}.stock.out span{background:var(--c-muted)}
.sku{flex:1;min-width:0;margin:0;font:700 12px/1.4 var(--body);letter-spacing:.5px;color:var(--c-2nd);text-align:right;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.checked{display:flex;align-items:center;gap:8px;height:34px;margin:10px 0 22px;font-size:12px;color:var(--c-2nd)}
.checked svg{flex:none;color:var(--primary)}
.cart{display:grid;grid-template-columns:152px minmax(0,1fr);gap:14px 16px}
.qty{display:flex;height:50px;border:1px solid var(--c-line);background:#fff}
.qty-step{display:grid;place-items:center;width:44px;border:0;background:none;color:var(--ink);cursor:pointer}
.qty-step:hover{background:rgba(0,0,0,.04)}
.qty label{flex:1;display:flex;border-inline:1px solid var(--c-line)}
.qty input{width:100%;min-width:0;border:0;background:none;font:700 15px var(--body);color:var(--ink);text-align:center;-moz-appearance:textfield}
.qty input::-webkit-inner-spin-button,.qty input::-webkit-outer-spin-button{-webkit-appearance:none;margin:0}
.add{display:flex;align-items:center;justify-content:center;gap:8px;height:50px;padding:0 16px;border:0;border-radius:5px;background:var(--primary);color:#fff;font:700 14px var(--body);cursor:pointer;transition:background .2s}
.add:hover{filter:brightness(1.1)}
.add .done,.add.is-done .idle{display:none}.add.is-done .done{display:block}.add.is-done{background:var(--c-ok)}
.buy-now{grid-column:1/-1;height:50px;border:1px solid var(--c-line);border-radius:5px;background:#fff;color:var(--primary);font:700 14px var(--body);cursor:pointer}
.buy-now:hover{background:color-mix(in srgb,var(--primary) 4%,#fff)}
.unavailable{margin:0;padding:12px 0;font:700 13px/1.4 var(--body);letter-spacing:1px;color:var(--c-2nd)}
.cart-note{display:flex;align-items:center;gap:8px;margin-top:14px;font-size:13px;line-height:1.4;color:var(--c-2nd)}
.cart-note svg{flex:none;color:var(--primary)}.cart-note span{flex:1}
.cart-note a{font-weight:700;color:var(--primary);text-decoration:none}
.cart-note[data-state=error] span{color:var(--bad)}
.promises{list-style:none;margin:28px 0 0;padding:0;border-top:1px solid var(--c-line)}
.promises li{display:flex;align-items:flex-start;gap:12px;padding:14px;border-bottom:1px solid var(--c-line)}
.promises li:last-child{border-bottom-color:transparent}
.promises .dot{flex:none;width:8px;height:8px;margin-top:5px;border-radius:50%;background:var(--primary)}
.promises div{flex:1;display:grid;gap:3px}
.promises strong{font:700 13px/1.4 var(--body);color:var(--ink)}
.promises div span{font-size:13px;line-height:1.45;color:var(--c-2nd)}
.promises svg{flex:none;color:var(--c-2nd)}
.details{margin-top:64px;padding-block:54px;background:#fff;scroll-margin-top:40px}
.details-in{max-width:1320px}
.section-title{margin:0;font:400 28px/1.2 var(--head);letter-spacing:.2px;text-transform:uppercase;color:var(--ink)}
.section-title::after{content:"";display:block;width:72px;height:2px;margin-top:10px;background:var(--primary)}
.section-title.accent{color:var(--primary)}
.sheet-row{display:grid;grid-template-columns:minmax(0,1fr) 340px;align-items:start;gap:56px;margin-top:32px}
.sheet{min-width:0;max-width:820px}
.sheet h3{margin:0;font:800 12px/1.4 var(--body);letter-spacing:1px;text-transform:uppercase;color:var(--primary)}
.description{max-width:720px;margin:10px 0 32px;font-size:15px;line-height:1.7;color:var(--ink)}.description p{margin:0 0 12px}
.group+.group{margin-top:28px}
.group dl{margin:8px 0 0}
.group dl>div{display:grid;grid-template-columns:5fr 7fr;padding:12px 0;border-bottom:1px solid var(--c-line)}
.group dt{padding:1px 16px 0 0;font-size:14px;line-height:1.4;color:var(--c-2nd)}
.group dd{margin:0}
.group .value{display:block;font:700 14.5px/1.4 var(--body);color:var(--ink)}
.group .detail{display:block;font-size:12.5px;line-height:1.4;color:var(--c-muted)}
.group .hint{grid-column:1/-1;margin:4px 0 0;font-size:12.5px;line-height:1.45;color:var(--c-muted)}
.origin{margin:16px 0 0;font-size:12.5px;color:var(--c-muted)}
.help{padding:22px;border:1px solid var(--c-line);border-radius:8px;background:var(--c-soft);color:var(--primary)}
.sheet-row.only-help{grid-template-columns:minmax(0,420px)}
.help-title{margin:12px 0 8px;font:400 17px/1.3 var(--head);color:var(--ink)}
.help p:not(.help-title){margin:0;font-size:14px;line-height:1.55;color:var(--c-2nd)}
.ask{display:flex;align-items:center;justify-content:center;gap:8px;height:46px;margin-top:16px;border:1px solid var(--primary);border-radius:5px;color:var(--primary);font:700 14px var(--body);text-decoration:none}
.ask:hover{background:color-mix(in srgb,var(--primary) 6%,transparent)}
.related{max-width:1320px;margin-block:80px 88px}
.related-box{container-type:inline-size;margin-top:28px}
.related-cards{--cols:2;--ratio:.66;display:grid;grid-template-columns:repeat(var(--cols),minmax(0,1fr));gap:24px 20px;list-style:none;margin:0;padding:0}
@container (min-width:820px){.related-cards{--cols:3;--ratio:.71}}
@container (min-width:1180px){.related-cards{--cols:4;--ratio:.73;gap:32px 28px}}
.related-cards .card .info{height:88px}
.related-cards .card a:hover{box-shadow:none}.related-cards .card .hover-bar{display:none}
.related-cards .card a:hover .maker{opacity:1}.related-cards .card a:hover .info{border-top-color:#e8e2d8}

/* Product cards (related products and the catalog grid): the card is
   _CatalogProductCard; the grid takes websiteCatalogGridMetrics' columns,
   ratios and gaps, read on the grid's own width (Flutter reads the window, so
   at 1000 px it squeezes four columns of 146 px beside the rail). The
   thresholds put a full desktop and a phone on Flutter's exact numbers. */
.cards-box{container-type:inline-size}
.cards{--cols:4;--ratio:.75;display:grid;grid-template-columns:repeat(var(--cols),minmax(0,1fr));gap:40px 34px;list-style:none;margin:0;padding:0}
.cards.compact{--cols:5;gap:40px 26px}.cards.editorial{--cols:4;--ratio:.82}
@container (max-width:987px){.cards,.cards.compact{--cols:4;--ratio:.72;gap:36px 28px}.cards.editorial{--cols:3;--ratio:.76}}
@container (max-width:859px){.cards,.cards.compact,.cards.editorial{--cols:3;--ratio:.69;gap:30px 22px}}
@container (max-width:567px){.cards,.cards.compact,.cards.editorial{--cols:2;--ratio:.63;gap:24px 18px}}
@container (max-width:367px){.cards,.cards.compact,.cards.editorial{--cols:2;--ratio:.58;gap:22px 16px}}
.card{min-width:0}
.card a{display:flex;flex-direction:column;aspect-ratio:var(--ratio);color:var(--ink);text-decoration:none;transition:background .22s cubic-bezier(.215,.61,.355,1),box-shadow .22s cubic-bezier(.215,.61,.355,1)}
.card .shot{position:relative;flex:1;min-height:0;background:#fff;overflow:hidden}
.card .shot img,.card .no-photo{position:absolute;top:10px;left:12px;width:calc(100% - 24px);height:calc(100% - 20px);object-fit:contain}
.card.has-brand .shot img,.card.has-brand .no-photo{height:calc(100% - 38px)}
.card .no-photo{display:grid;place-items:center;color:#e0e0e0}
.card .maker{position:absolute;left:12px;right:12px;bottom:6px;font:600 10px/14px var(--body);letter-spacing:.45px;text-transform:uppercase;color:#9e9e9e;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card .hover-bar{position:absolute;left:0;right:0;bottom:0;height:0;display:flex;align-items:center;gap:12px;padding:0 12px;background:rgba(11,58,95,.78);color:#fff;opacity:0;overflow:hidden;transition:height .22s cubic-bezier(.215,.61,.355,1),opacity .22s cubic-bezier(.215,.61,.355,1)}
.card .hover-bar span{font:700 10px/14px var(--body);letter-spacing:.65px;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card .hover-bar span:first-child{flex:1}.card .hover-bar span:last-child{font-weight:800;letter-spacing:.75px}
.card .info{flex:none;height:90px;padding:12px 8px 10px;border-top:1px solid #e8e2d8;display:flex;flex-direction:column;gap:4px;transition:border-color .22s cubic-bezier(.215,.61,.355,1)}
.card .name{font:800 13px/1.3 var(--body);letter-spacing:.2px;text-transform:uppercase;color:rgba(0,0,0,.87);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.card .p{font:800 16px/1.2 var(--body);color:#000;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
@media (hover:hover){
.card a:hover{background:#fff;box-shadow:0 18px 34px 2px rgba(0,0,0,.10)}
.card a:hover .hover-bar{height:42px;opacity:1}.card a:hover .maker{opacity:0}.card a:hover .info{border-top-color:transparent}
}
@media (prefers-reduced-motion:reduce){.card a,.card .hover-bar,.card .info{transition:none}}

/* Catalog: product_catalog_page.dart and catalog_collection_presentation.dart */
.hero{position:relative;display:grid;align-items:center;height:var(--hero,130px);color:#fff;background:linear-gradient(90deg,#0c2234,#315266);overflow:hidden}
.hero img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.hero::after{content:"";position:absolute;inset:0;background:rgba(0,0,0,var(--shade,.35))}
.hero .wrap{position:relative;z-index:1;width:100%;max-width:1504px;padding:24px 56px}
.hero.center .wrap{text-align:center}.hero.center .hero-text{margin-inline:auto}
.hero-text{max-width:720px}
.eyebrow{margin:0 0 12px;font:800 11px/1.2 var(--body);letter-spacing:1.8px;text-transform:uppercase}
.hero h1{margin:0;font:900 48px/.98 var(--body);letter-spacing:.8px;text-transform:uppercase;color:#fff}
.hero-intro{margin:16px 0 0;font-size:16px;line-height:1.5;color:rgba(255,255,255,.92);display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden}
.subcats{border-block:1px solid #eee}
.subcats ul{display:flex;gap:22px;list-style:none;margin:0;padding:13px 0;overflow-x:auto;scrollbar-width:none}
.subcats a{display:block;padding:8px 0;font:800 11px/1.2 var(--body);letter-spacing:.7px;text-transform:uppercase;color:rgba(0,0,0,.87);text-decoration:none;white-space:nowrap}
.subcats a:hover{color:var(--primary)}
.top .wrap,.catalog.wrap,.subcats .wrap{max-width:1560px;padding-inline:28px}
.catalog{display:grid;grid-template-columns:236px minmax(0,1fr);gap:40px;padding-block:33px 30px;align-items:start}
.filters-panel,.results{min-width:0}
.filters{display:flex;flex-direction:column}
.sheet-head .grab,.sheet-close,.sheet-dim,.sort-sheet,.sheet-check,.bar-button{display:none}
.side-title{margin:0 0 20px;font:600 16px/1.3 var(--body);letter-spacing:.2px;color:rgba(0,0,0,.87)}
.search{display:flex;margin:0 0 24px}
.search input{width:100%;height:48px;border:1px solid #d7d7d7;border-radius:4px;padding:0 16px 0 48px;font:400 14px var(--body);color:var(--ink);background:#f5f5f5 url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='%23bdbdbd' d='M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z'/%3E%3C/svg%3E") no-repeat 14px center/20px}
.search input::placeholder{color:#9e9e9e}
.search input:focus-visible{outline:none;border-color:var(--primary);box-shadow:inset 0 0 0 1px var(--primary)}
.facet+.facet{margin-top:18px;padding-top:18px;border-top:1px solid #eee}
.facet h2{display:flex;align-items:center;gap:6px;margin:0 0 11px;font:700 14px/20px var(--body);letter-spacing:.2px;text-transform:none;color:rgba(0,0,0,.87)}
.facet:has(.check) h2{margin-bottom:8px}.facet:has(.onward) h2{margin-bottom:4px}
.facet h2 .info{display:flex;color:rgba(0,0,0,.45);cursor:help}
.facet ul{list-style:none;margin:0;padding:0}
.tree .all{margin-bottom:4px}
.tree .row{display:flex;align-items:center}
.tree .chev{flex:none;display:flex;align-items:center;width:22px;height:20px;color:#757575;cursor:pointer}
.tree .chev svg{transition:transform .2s}
.branch,.more-check{position:absolute;opacity:0;pointer-events:none}
.branch:checked+.row .chev svg{transform:rotate(90deg)}
.branch:focus-visible+.row .chev{outline:3px solid var(--accent);border-radius:4px}
.branch:not(:checked)~ul{display:none}
.tree a{flex:1;min-width:0;display:flex;align-items:center;gap:10px;padding:8px 0;font:400 13px/20px var(--body);color:#616161;text-decoration:none}
.tree a:hover{color:#000}
.tree .radio{flex:none;display:grid;place-items:center;width:16px;height:16px;border:1.5px solid #bdbdbd;border-radius:50%;color:#fff}
.tree a[aria-current]{color:#000;font-weight:600}.tree a[aria-current] .radio{background:#000;border-color:#000}
.onward a{display:flex;align-items:center;min-height:48px;padding:6px 0;font:500 13px/1.3 var(--body);color:#424242;text-decoration:none}
.onward a>span:first-child{flex:1;min-width:0}
.onward a:hover{color:#000}.onward a[aria-current]{color:#000;font-weight:700;cursor:default}
.onward .n{margin-left:8px;font:600 12px var(--body);color:#757575}
.onward svg{margin-left:2px;color:#9e9e9e}.onward .go-gap{width:18px}
.check{display:flex;align-items:center;gap:6px;padding:5px 0;font:400 13px/20px var(--body);color:rgba(0,0,0,.87);cursor:pointer}
.check input{appearance:none;-webkit-appearance:none;flex:none;width:18px;height:18px;margin:7px;border:2px solid #616161;border-radius:2px;background:#fff;cursor:pointer}
.check input:checked{border-color:var(--primary);background:var(--primary) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='%23fff' d='M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z'/%3E%3C/svg%3E") center/14px no-repeat}
.check-text{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.check:has(:checked) .check-text{font-weight:600}
.check .n{font-size:12px;color:#9e9e9e}
.check.strong{gap:8px;padding:4px 0}.check.strong .check-text{font-weight:600;white-space:normal}
.more-check:not(:checked)~.more-rows{display:none}
.more{display:inline-flex;align-items:center;min-height:40px;padding:6px 0;font:600 14px/20px var(--body);color:var(--primary);cursor:pointer}
.more .when-open,.more-check:checked~.more .when-closed{display:none}
.more-check:checked~.more .when-open{display:inline}
.more-check:focus-visible~.more{outline:3px solid var(--accent);outline-offset:2px}
.range{margin:4px 0 0;font-size:12px;color:#757575}
.price-range{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}
.field{position:relative;display:block}
.field input{width:100%;height:40px;border:1px solid #8e8e8e;border-radius:4px;padding:0 10px;font:400 14px var(--body);color:var(--ink);background:#fff;-moz-appearance:textfield}
.field input::-webkit-inner-spin-button,.field input::-webkit-outer-spin-button{-webkit-appearance:none;margin:0}
.field-label,.field-prefix{position:absolute;left:10px;top:50%;transform:translateY(-50%);font:400 14px/1 var(--body);color:#616161;pointer-events:none}
.field-label{margin-left:-4px;padding:0 4px;background:#fff;transition:top .15s,font-size .15s}
.field-prefix{opacity:0}
.field input:focus,.field input:not(:placeholder-shown){padding-left:22px}
.field input:focus~.field-label,.field input:not(:placeholder-shown)~.field-label{top:0;font-size:11px}
.field input:focus~.field-prefix,.field input:not(:placeholder-shown)~.field-prefix{opacity:1}
.field input:focus{outline:none;border:2px solid var(--primary);padding-left:21px}
.field input:focus~.field-label{color:var(--primary)}
.price-actions{display:flex;align-items:center;gap:4px;margin-top:8px}
.apply-now{flex:1;height:40px;border:1.5px solid var(--primary);border-radius:8px;background:transparent;color:var(--primary);font:600 14px var(--body);cursor:pointer}
.apply-now:hover{background:color-mix(in srgb,var(--primary) 8%,transparent)}
.price-clear{display:grid;place-items:center;width:40px;height:40px;border-radius:50%;color:var(--on-variant)}
.price-clear:hover{background:var(--soft)}
.apply{margin-top:8px;height:40px;padding:0 14px;border:1px solid var(--ink);border-radius:8px;background:#fff;color:var(--ink);font:600 13px var(--body);cursor:pointer}
.js .apply{display:none}
.results{container-type:inline-size}
.results-head{display:grid;grid-template-columns:minmax(0,1fr) auto;grid-template-areas:"h c" "n n" "s s";column-gap:24px;align-items:center}
.results-head>.trail{grid-area:h}
.controls{grid-area:c;display:flex;align-items:center}
.count{grid-area:n;margin:11px 0 0;font-size:13px;line-height:1.4;color:#757575}.count .narrow{display:none}
.scope{grid-area:s;display:flex;flex-wrap:wrap;gap:4px 10px;margin:5px 0 0;font-size:12.5px;color:#475569}.scope a{font-weight:700;text-decoration:none}
@container (max-width:819px){.results-head{grid-template-columns:minmax(0,1fr);grid-template-areas:"h" "c" "n" "s"}.controls{justify-self:end;margin-top:12px}}
.trail{position:relative;display:flex;flex-wrap:wrap;align-items:center;gap:4px 8px;margin:0;padding-left:16px;font:700 20px/1.2 var(--body);letter-spacing:.5px;color:#000}
.trail::before{content:"";position:absolute;left:0;top:50%;width:4px;height:24px;margin-top:-12px;background:#000}
.trail a{padding:2px 0;color:#616161;font-weight:600;text-decoration:none}.trail a:hover{color:#000}
.trail strong{padding:2px 0;color:#000;font-weight:800}
.trail a+a::before,.trail a+strong::before{content:"/";margin-right:8px;color:#bdbdbd;font-weight:500}
.order{display:flex;flex-wrap:wrap;align-items:center;gap:12px 16px}
.order label{display:flex;align-items:center;gap:8px;font-size:13px;color:#757575}
.order select{appearance:none;-webkit-appearance:none;height:26px;border:1px solid #e0e0e0;border-radius:0;padding:0 36px 0 12px;font:400 13px var(--body);color:rgba(0,0,0,.87);background:#fff url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='%23616161' d='M7 10l5 5 5-5z'/%3E%3C/svg%3E") no-repeat right 12px center/24px;cursor:pointer}
.notice{margin:12px 0 0;padding:10px 14px;border-radius:8px;background:#fff4e5;color:#7a3e00;font-size:14px}
.cards-box,.empty{margin-top:30px}
.empty{display:grid;justify-items:center;padding:64px;text-align:center;color:#757575;font-size:13px}
.empty svg{margin-bottom:16px;color:#bdbdbd}.empty p{margin:0}
.empty-title{margin-bottom:8px!important;font:500 16px/1.4 var(--body);color:rgba(0,0,0,.54)}
.pager{display:flex;justify-content:center;align-items:center;flex-wrap:wrap;margin-top:32px}
.pager .step{display:inline-flex;align-items:center;min-height:40px;padding:10px 14px;border-radius:20px;color:#616161;font:600 14px/20px var(--body);text-decoration:none}
.pager .step:hover{background:color-mix(in srgb,var(--primary) 8%,transparent)}
.pager .step-gap{width:100px}
.pager>:first-child{margin-right:16px}.pager>:last-child{margin-left:16px}
.pager .num{display:grid;place-items:center;width:36px;height:36px;margin:0 2px;border-radius:4px;font:400 14px var(--body);color:#616161;text-decoration:none}
.pager a.num:hover{background:rgba(0,0,0,.05)}
.pager .num[aria-current]{background:#b71c1c;color:#fff;font-weight:600}
.pager .gap{padding:0 4px;color:#757575}

/* Oswald «bold» as Flutter draws it: the default weight with the outline
   emboldened (Skia's fake bold), so the letters keep their 400 advances. */
.buy h1,.price,.highlights dd,.section-title,.help-title,.foot-title,.foot-sec summary,.follow,.foot-name,.logo-name,.notfound h1{-webkit-text-stroke:.032em currentColor}
/* Footer: public_store_layout.dart, _buildFooter from 800 px up and
   _buildMobileFooter below. The brand glyphs are Font Awesome's, from the
   font Flutter's build already serves. */
@font-face{font-family:FaBrands;src:url(/assets/packages/font_awesome_flutter/lib/fonts/fa-brands-400.ttf) format("truetype");font-display:block}
.fab{font:normal 22px/1 FaBrands}
.foot{background:var(--foot);color:rgba(255,255,255,.7)}
.foot a{color:inherit;text-decoration:none}.foot a:hover{color:#fff}
.foot ul{list-style:none;margin:0;padding:0}
.foot-wide{max-width:1248px;margin:0 auto;padding:24px}
.foot-grid{display:flex;flex-wrap:wrap;justify-content:center;gap:24px 32px}
.foot-brand{width:250px}.foot-col{width:200px}
.foot-logo{display:flex}.foot-logo img{height:60px;width:auto;max-width:250px;object-fit:contain;filter:brightness(0) invert(1)}
.foot-name{font:400 26px var(--head);color:#fff;text-transform:uppercase}
.foot-about{margin:16px 0 0;font-size:16px;line-height:1.5}
.foot-social{display:flex;flex-wrap:wrap;gap:8px;margin-top:24px}
.foot-social a{display:grid;place-items:center;width:40px;height:40px;border-radius:50%}
.foot-social a:hover{background:rgba(255,255,255,.08)}
.foot-title{margin:0 0 16px;font:400 16px/1.5 var(--head);letter-spacing:.15px;color:#fff}
.foot-col li{padding-bottom:8px;font-size:14px;line-height:21px}
.foot .contact li{display:flex;align-items:flex-start;gap:8px;padding-bottom:12px}
.foot .contact svg{flex:none}
.payments{margin-top:32px;text-align:center}
.payments p{margin:0 0 16px;font-size:11px;line-height:1.4;letter-spacing:.5px;color:rgba(255,255,255,.6)}
.payments ul{display:flex;justify-content:center;align-items:center;flex-wrap:wrap;gap:12px}
.pay-logo{display:block;width:150px;height:60px;object-fit:contain}
.pay-chip{display:inline-flex;align-items:center;gap:7px;height:32px;padding:0 10px;border-radius:6px;border:1px solid rgba(255,255,255,.24);background:rgba(255,255,255,.1);color:rgba(255,255,255,.7);font:600 11px var(--body)}
.foot-rule{margin:0;border:0;border-top:1px solid rgba(255,255,255,.24)}
.legal{margin:24px 0 0;font-size:14px;line-height:1.4;text-align:center}
.foot-narrow{display:none;padding:32px 16px 24px}
@media (max-width:799px){
.foot-wide{display:none}.foot-narrow{display:block}
.foot-narrow>.foot-logo{display:flex;justify-content:center;margin-bottom:32px}.foot-narrow>.foot-logo img{height:50px}
.foot-sec summary{display:flex;align-items:center;justify-content:space-between;min-height:54px;padding:0 16px;font:400 14px/1.4 var(--head);letter-spacing:1px;color:#fff;cursor:pointer;list-style:none}
.foot-sec summary::-webkit-details-marker{display:none}
.foot-sec summary svg{transition:transform .2s}.foot-sec[open] summary svg{transform:rotate(180deg)}
.foot-sec>ul{padding:0 0 16px 16px}
.foot-sec li>a,.foot-sec li>span{display:inline-block;padding:8px 0;font-size:16px;line-height:1.5}
.foot-sec .contact li{gap:12px;padding:0}.foot-sec .contact svg{width:18px;height:18px;margin-top:11px}
.follow{margin:32px 0 16px;padding:0 16px;font:400 14px/1.4 var(--head);letter-spacing:1px;color:#fff}
.foot-social.round{margin:0;padding:0 16px}
.foot-social.round a{width:48px;height:48px;background:rgba(255,255,255,.1);color:#fff}
.foot-narrow .legal{margin-top:32px;color:rgba(255,255,255,.54)}
}
.chat-fab{position:fixed;right:20px;bottom:20px;z-index:9;display:grid;place-items:center;width:58px;height:58px;border-radius:16px;background:#111827;color:#fff;box-shadow:0 10px 30px rgba(15,23,42,.3)}
.chat-fab:hover{background:#000}
.mark-note{position:fixed;left:50%;transform:translateX(-50%);bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:30;max-width:calc(100% - 32px);padding:12px 16px;border-radius:10px;background:#1f2328;color:#fff;font:500 14px/1.4 var(--body);box-shadow:0 6px 24px rgba(0,0,0,.25);text-align:center}
.holding{min-height:100vh;display:grid;place-content:center;gap:8px;padding:24px;text-align:center}
.notfound{padding-block:72px 96px;max-width:640px}.notfound h1{margin:0 0 12px;font:400 32px/1.15 var(--head);text-transform:uppercase;color:var(--ink)}.notfound p{color:var(--muted)}
.notfound a.primary-link{display:inline-block;margin-top:18px;padding:14px 22px;border-radius:12px;background:var(--primary);color:#fff;font-weight:600;text-decoration:none}

@media (min-width:1080px){.nav-no-desktop{display:none!important}}
@media (max-width:1079px){.nav-no-mobile{display:none!important}
.top .wrap.bar{padding-inline:16px}
.bar{height:68px}.logo{order:1;margin-right:auto}.logo img{height:40px;max-width:140px;object-fit:contain;object-position:left center}
.tools{order:2;gap:4px;margin-left:16px}.tools>a{width:48px;height:48px}.tools>a svg{width:23px;height:23px}.tools .login{display:none}
.menu{display:none}
.menu-button{display:flex;align-items:center;justify-content:center;width:48px;height:48px;cursor:pointer;color:var(--ink);border-radius:50%}.menu-button svg{width:23px;height:23px}
.menu-toggle:focus-visible~.bar .menu-button{outline:3px solid var(--accent);outline-offset:-4px}
.sheet-scrim{position:fixed;inset:0;z-index:30;background:rgba(0,0,0,.54)}
.menu-sheet{position:fixed;left:0;right:0;bottom:0;z-index:31;max-height:calc(100vh - 48px);overflow-y:auto;background:#fff;border-radius:20px 20px 0 0;padding:12px 0 calc(24px + env(safe-area-inset-bottom,0px))}
.menu-toggle:checked~.sheet-scrim{display:block;animation:vb-fade .25s ease-out}
.menu-toggle:checked~.menu-sheet{display:block;animation:vb-sheet .25s cubic-bezier(.2,0,0,1)}
body:has(.menu-toggle:checked){overflow:hidden}
.sheet-handle{display:block;width:40px;height:4px;margin:0 auto 24px;border-radius:2px;background:var(--outline-variant)}
.menu-sheet hr{margin:8px 24px;border:0;border-top:1px solid var(--outline-variant)}
.sheet-item{display:flex;align-items:center;gap:16px;padding:14px 20px 14px 24px;color:var(--ink);text-decoration:none;font:500 16px/24px var(--body);letter-spacing:.1px;cursor:pointer;list-style:none}
.sheet-item>svg{flex:none;width:21px;height:21px}.sheet-item>svg.go{width:20px;height:20px;color:var(--on-variant)}
.sheet-item>span{flex:1;min-width:0;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.sheet-item:hover{background:color-mix(in srgb,var(--primary) 4.5%,transparent)}
.sheet-login,.sheet-all{color:var(--primary)}
summary.sheet-item::-webkit-details-marker{display:none}
.sheet-group>summary>svg:first-child{color:var(--on-variant)}.sheet-group>summary>span{font:600 14px/20px var(--body)}
.sheet-group>summary>svg.go{width:24px;height:24px;transition:transform .2s}
.sheet-group[open]{background:color-mix(in srgb,var(--primary) 3.5%,transparent)}
.sheet-group[open]>summary>svg.go{transform:rotate(180deg);color:var(--primary)}
.sheet-group>.sheet-item:not(summary),.sheet-group>.sheet-group{margin-left:12px}
}
@keyframes vb-sheet{from{transform:translateY(100%)}to{transform:none}}
@keyframes vb-fade{from{opacity:0}to{opacity:1}}
@media (max-width:359px){.top .wrap.bar{padding-inline:12px}.logo img{height:34px;max-width:110px}.tools{margin-left:8px}}
@media (max-width:1099px){
.pdp,.details-in,.related{width:calc(100% - 48px)}
.product{grid-template-columns:minmax(0,52fr) minmax(0,48fr);column-gap:32px}
}
@media (max-width:767px){
.pdp,.details-in,.related{width:calc(100% - 32px)}.pdp{margin-top:18px}
.crumbs{display:none}
.product{grid-template-columns:minmax(0,1fr);row-gap:24px}
.stage{height:clamp(300px,88cqw,420px)}.stage img{inset:2px;width:calc(100% - 4px);height:calc(100% - 4px)}
.thumbs{gap:12px;margin-top:16px}.thumbs button{width:72px;height:72px}
.buy h1{font-size:30px;line-height:1.18}.buy hr{margin:20px 0}.price{font-size:38px}
.highlights{margin-top:20px}
.checked{margin-bottom:18px}
.cart{grid-template-columns:minmax(0,1fr)}.buy-now{height:52px}
.details{margin-top:48px;padding-block:42px}
.sheet-row{grid-template-columns:minmax(0,1fr);gap:32px;margin-top:24px}.sheet{max-width:none}
.related{margin-block:56px 72px}
}
@media (max-width:699px){
.hero{height:var(--hero-phone,130px)}.hero .wrap{padding:16px 22px}.hero h1{font-size:32px}.hero-intro{font-size:14px;-webkit-line-clamp:3}
.subcats .wrap,.catalog.wrap{padding-inline:16px}.subcats ul{padding:10px 0}
.catalog{display:block;padding-block:22px 16px}
.results-head{grid-template-columns:minmax(0,1fr);grid-template-areas:"h" "n" "s" "c"}
.trail{font-size:18px}
.count{margin-top:9px}.count .wide{display:none}.count .narrow{display:inline}
.controls{justify-self:stretch;gap:24px;margin:14px -16px 0;padding:12px 16px;border-bottom:1px solid #eee}
.order{display:none}
.bar-button{display:inline-flex;align-items:center;gap:6px;font:400 14px/20px var(--body);letter-spacing:.2px;color:#616161;cursor:pointer}
.bar-button:last-of-type{gap:4px}
.sheet-check{display:block;position:absolute;opacity:0;pointer-events:none}
.sheet-check:focus-visible+.bar-button{outline:3px solid var(--accent);outline-offset:2px}
.cards-box,.empty{margin-top:25px}
.sheet-dim{position:fixed;inset:0;z-index:30;background:rgba(0,0,0,.54)}
.sheet-panel{position:fixed;left:0;right:0;bottom:0;z-index:31;display:none;flex-direction:column;background:#fff;border-radius:16px 16px 0 0}
.filters.sheet-panel{height:70vh;height:70dvh;max-height:90vh}
.sheet-head{display:flex;flex-wrap:wrap;align-items:center;padding:0 16px;border-bottom:1px solid var(--line)}
.sheet-head .grab{display:flex;flex:0 0 100%;justify-content:center;padding-top:12px}
.sheet-head .grab::before{content:"";width:40px;height:4px;border-radius:2px;background:#e0e0e0}
.sheet-head .side-title{flex:1;margin:16px 0;font:700 18px/48px var(--body);letter-spacing:0}
.sheet-close{display:grid;place-items:center;width:48px;height:48px;margin-right:-12px;border-radius:50%;color:var(--ink);cursor:pointer}
.sheet-close:hover{background:rgba(0,0,0,.05)}
.sheet-body{flex:1;min-height:0;overflow-y:auto;padding:16px 16px calc(16px + env(safe-area-inset-bottom,0px))}
.catalog:has(#filtros:checked) .filters,.results:has(#orden:checked) .sort-sheet{display:flex;animation:vb-sheet .25s cubic-bezier(.2,0,0,1)}
.catalog:has(#filtros:checked) .filters-panel>.sheet-dim,.results:has(#orden:checked)>.sheet-dim{display:block;animation:vb-fade .25s ease-out}
body:has(.sheet-check:checked){overflow:hidden}
.sort-sheet ul{list-style:none;margin:0;padding:0 0 calc(16px + env(safe-area-inset-bottom,0px))}
.sort-sheet a{display:flex;align-items:center;justify-content:space-between;min-height:56px;padding:0 24px 0 16px;font:400 16px/24px var(--body);color:rgba(0,0,0,.87);text-decoration:none}
.sort-sheet a[aria-current]{font-weight:600}.sort-sheet a:hover{background:rgba(0,0,0,.04)}
.pager .step span{display:none}.pager .step{padding:8px}.pager .step-gap{width:40px}
.pager>:first-child{margin-right:4px}.pager>:last-child{margin-left:4px}
}
@media (max-width:760px){
body{font-size:16px}.wrap{padding-inline:16px}
}
}
''';
